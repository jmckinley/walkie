// walkie-proxy/worker.js
// Cloudflare Worker — Walkie AI proxy
//
// Deploy: wrangler deploy
// Set secrets:
//   wrangler secret put GEMINI_API_KEY
//   wrangler secret put WALKIE_SHARED_SECRET   (a random string your app sends)
//
// KV namespace: WALKIE_RATE_LIMITS
//   wrangler kv:namespace create WALKIE_RATE_LIMITS
//   Add to wrangler.toml: [[kv_namespaces]] binding="WALKIE_RATE_LIMITS" id="<id>"

const TRIAL_DAYS           = 60;
const FREE_DAILY_LIMIT     = 10;
const PAID_MONTHLY_LIMIT   = 200;   // $3.99/mo
const PAID_ANNUAL_LIMIT    = 200;   // $24.99/yr — same daily limit, better value framing
const GEMINI_MODEL         = "gemini-2.0-flash";        // flash required for search grounding
const GEMINI_AUDIO_MODEL   = "gemini-2.5-flash";        // 2.5 Flash required for native audio output
const GEMINI_ENDPOINT      = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;
const GEMINI_AUDIO_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_AUDIO_MODEL}:generateContent`;

// ─── Main handler ────────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === "OPTIONS") {
      return corsResponse(new Response(null, { status: 204 }));
    }

    if (request.method !== "POST") {
      return corsResponse(new Response("Method not allowed", { status: 405 }));
    }

    const url = new URL(request.url);

    try {
      switch (url.pathname) {
        case "/v1/chat":     return await handleChat(request, env);
        case "/v1/register": return await handleRegister(request, env);
        case "/v1/status":   return await handleStatus(request, env);
        case "/v1/tts":      return await handleTTS(request, env);
        default:             return corsResponse(new Response("Not found", { status: 404 }));
      }
    } catch (err) {
      console.error(err);
      return corsResponse(json({ error: err.message }, 500));
    }
  }
};

// ─── Register device (called on first launch) ─────────────────────────────────
// Returns: { deviceId, tier, trialEndsAt, requestsToday, dailyLimit }

async function handleRegister(request, env) {
  const body = await request.json();
  const { deviceId } = body;

  if (!deviceId || typeof deviceId !== "string" || deviceId.length < 8) {
    return corsResponse(json({ error: "Invalid deviceId" }, 400));
  }

  const key   = `device:${deviceId}`;
  const existing = await env.WALKIE_RATE_LIMITS.get(key, { type: "json" });

  if (existing) {
    return corsResponse(json(publicStatus(existing)));
  }

  // New device — start trial
  const record = {
    deviceId,
    tier:          "free_trial",
    trialStartedAt: Date.now(),
    createdAt:      Date.now(),
    requestsToday:  0,
    dayKey:         todayKey(),
  };

  await env.WALKIE_RATE_LIMITS.put(key, JSON.stringify(record), {
    expirationTtl: 60 * 60 * 24 * 365  // 1 year
  });

  return corsResponse(json(publicStatus(record)));
}

// ─── Status check ─────────────────────────────────────────────────────────────

async function handleStatus(request, env) {
  const body     = await request.json();
  const { deviceId } = body;
  const record   = await getDevice(deviceId, env);
  if (!record) return corsResponse(json({ error: "Device not found" }, 404));
  return corsResponse(json(publicStatus(record)));
}

// ─── Chat ─────────────────────────────────────────────────────────────────────

async function handleChat(request, env) {
  const body = await request.json();
  const { deviceId, messages, appSecret } = body;

  // Verify the app secret (prevents random internet access)
  if (appSecret !== env.WALKIE_SHARED_SECRET) {
    return corsResponse(json({ error: "Unauthorized" }, 401));
  }

  if (!deviceId || !messages) {
    return corsResponse(json({ error: "Missing deviceId or messages" }, 400));
  }

  // Validate messages array to prevent token amplification abuse
  if (!Array.isArray(messages) || messages.length > 22) {
    return corsResponse(json({ error: "messages must be an array of at most 22 items" }, 400));
  }
  for (const msg of messages) {
    if (typeof msg.content !== "string" || msg.content.length > 2000) {
      return corsResponse(json({ error: "Each message content must be a string under 2000 characters" }, 400));
    }
  }

  // Load device record
  const record = await getDevice(deviceId, env);
  if (!record) return corsResponse(json({ error: "Device not registered" }, 404));

  // Check tier validity
  const status = computeStatus(record);
  if (!status.canSendRequest) {
    return corsResponse(json({
      error:     status.reason,
      tier:      status.tier,
      upgradeRequired: status.upgradeRequired,
    }, 429));
  }

  // Increment usage counter
  await incrementUsage(record, env);

  // Forward to Gemini
  const geminiResponse = await callGemini(messages, env);
  if (!geminiResponse.ok) {
    const errText = await geminiResponse.text();
    return corsResponse(json({ error: `Gemini error: ${errText.slice(0, 200)}` }, 502));
  }

  const geminiData = await geminiResponse.json();
  const text = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";

  // Generate high-quality audio from the text response (Gemini 2.5 Flash TTS)
  let audioBase64   = null;
  let audioMimeType = null;
  if (text) {
    const audioResult = await callGeminiAudio(text, env);
    if (audioResult) {
      audioBase64   = audioResult.data;
      audioMimeType = audioResult.mimeType;
    }
  }

  return corsResponse(json({
    text,
    audio:         audioBase64,
    audioMimeType: audioMimeType,
    usage: {
      tier:          status.tier,
      requestsToday: status.requestsToday + 1,
      dailyLimit:    status.dailyLimit,
      trialEndsAt:   status.trialEndsAt,
    }
  }));
}

// ─── Gemini call ──────────────────────────────────────────────────────────────

async function callGemini(messages, env) {
  // messages = [{role: "user"|"model", content: "..."}]
  const systemMsg = messages.find(m => m.role === "system");
  const chatMsgs  = messages.filter(m => m.role !== "system");

  // Prepend today's date so the model can reason correctly about recency
  const datePrefix = `Today's date is ${new Date().toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" })}. Use this to reason correctly about whether past events have occurred and defer to this date when assessing recency.\n\n`;
  const systemText = systemMsg ? datePrefix + systemMsg.content : datePrefix;

  const contents = chatMsgs.map(m => ({
    role:  m.role === "assistant" ? "model" : "user",
    parts: [{ text: m.content }]
  }));

  // google_search grounding gives the model live web results — requires gemini-2.0-flash or better
  const body = {
    contents,
    systemInstruction: { parts: [{ text: systemText }] },
    generationConfig: {
      maxOutputTokens: 300,
      temperature:     0.7,
    },
    tools: [{ google_search: {} }],
  };

  return fetch(`${GEMINI_ENDPOINT}?key=${env.GEMINI_API_KEY}`, {
    method:  "POST",
    headers: { "Content-Type": "application/json" },
    body:    JSON.stringify(body),
  });
}

// ─── TTS endpoint (BYOK users without a Gemini key) ──────────────────────────
// POST /v1/tts { appSecret, text } → { audio: base64PCM, audioMimeType }
// No per-device rate limiting — protected by appSecret only.

async function handleTTS(request, env) {
  const body = await request.json();
  const { text, appSecret } = body;

  if (appSecret !== env.WALKIE_SHARED_SECRET) {
    return corsResponse(json({ error: "Unauthorized" }, 401));
  }
  if (!text || typeof text !== "string" || text.length > 2000) {
    return corsResponse(json({ error: "Invalid text" }, 400));
  }

  const audioResult = await callGeminiAudio(text, env);
  if (!audioResult) {
    return corsResponse(json({ error: "TTS generation failed" }, 502));
  }

  return corsResponse(json({
    audio:         audioResult.data,
    audioMimeType: audioResult.mimeType,
  }));
}

// ─── Gemini TTS audio call ────────────────────────────────────────────────────
// Converts AI text response to high-quality speech via Gemini 2.5 Flash audio modality.
// Returns { data: base64PCM, mimeType } or null on failure (caller falls back to device TTS).

async function callGeminiAudio(text, env) {
  const body = {
    contents: [{
      role:  "user",
      parts: [{ text: `Say this naturally and conversationally: ${text}` }]
    }],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: {
        voiceConfig: {
          prebuiltVoiceConfig: { voiceName: "Charon" }
        }
      }
    }
  };

  try {
    const res = await fetch(`${GEMINI_AUDIO_ENDPOINT}?key=${env.GEMINI_API_KEY}`, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify(body),
    });
    if (!res.ok) return null;
    const data       = await res.json();
    const inlineData = data?.candidates?.[0]?.content?.parts?.[0]?.inlineData;
    if (!inlineData?.data) return null;
    return { data: inlineData.data, mimeType: inlineData.mimeType ?? "audio/pcm;rate=24000" };
  } catch {
    return null;
  }
}

// ─── Tier / rate limit logic ──────────────────────────────────────────────────

function computeStatus(record) {
  const today         = todayKey();
  const requestsToday = record.dayKey === today ? (record.requestsToday ?? 0) : 0;

  const trialEndsAt  = record.trialStartedAt + TRIAL_DAYS * 86400 * 1000;
  const trialExpired = record.tier === "free_trial" && Date.now() > trialEndsAt;
  const tier         = trialExpired ? "expired" : record.tier;

  if (tier === "expired") {
    return { tier, canSendRequest: false, upgradeRequired: true, reason: "Trial expired. Upgrade to continue." };
  }

  const dailyLimit = (tier === "paid_monthly" || tier === "paid_annual")
    ? PAID_MONTHLY_LIMIT
    : FREE_DAILY_LIMIT;

  if (requestsToday >= dailyLimit) {
    return {
      tier, canSendRequest: false, upgradeRequired: false,
      reason: `Daily limit reached (${dailyLimit}/day). Resets at midnight.`,
      requestsToday, dailyLimit, trialEndsAt,
    };
  }

  return { tier, canSendRequest: true, requestsToday, dailyLimit, trialEndsAt };
}

async function incrementUsage(record, env) {
  const today  = todayKey();
  const newRecord = {
    ...record,
    requestsToday: record.dayKey === today ? (record.requestsToday ?? 0) + 1 : 1,
    dayKey: today,
  };
  await env.WALKIE_RATE_LIMITS.put(
    `device:${record.deviceId}`,
    JSON.stringify(newRecord),
    { expirationTtl: 60 * 60 * 24 * 365 }
  );
}

// Called by your server-side RevenueCat webhook to upgrade tier
// POST /v1/upgrade { deviceId, tier: "paid_shared" | "free_trial", webhookSecret }
// Add this route if needed — omitted for brevity but pattern is the same

// ─── Device helpers ───────────────────────────────────────────────────────────

async function getDevice(deviceId, env) {
  if (!deviceId) return null;
  return env.WALKIE_RATE_LIMITS.get(`device:${deviceId}`, { type: "json" });
}

function publicStatus(record) {
  const s = computeStatus(record);
  return {
    tier:          s.tier,
    requestsToday: s.requestsToday ?? 0,
    dailyLimit:    s.dailyLimit,
    canSendRequest: s.canSendRequest,
    trialEndsAt:   s.trialEndsAt,
    trialDaysLeft: s.trialEndsAt
      ? Math.max(0, Math.ceil((s.trialEndsAt - Date.now()) / 86400000))
      : null,
    upgradeRequired: s.upgradeRequired ?? false,
  };
}

// ─── Utils ────────────────────────────────────────────────────────────────────

function todayKey() {
  return new Date().toISOString().slice(0, 10);  // "2026-03-28"
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" }
  });
}

function corsResponse(response) {
  const r = new Response(response.body, response);
  r.headers.set("Access-Control-Allow-Origin",  "*");
  r.headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  r.headers.set("Access-Control-Allow-Headers", "Content-Type");
  return r;
}
