const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== "POST") {
      return jsonResponse({ error: "Use POST to send a chat message." }, 405);
    }

    if (!env.GEMINI_API_KEY) {
      return jsonResponse({ error: "The AI service is not configured." }, 503);
    }

    const declaredLength = Number(request.headers.get("content-length") || 0);
    if (declaredLength > 16_000) {
      return jsonResponse({ error: "The request is too large." }, 413);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return jsonResponse({ error: "The request must contain valid JSON." }, 400);
    }

    if (
      !body ||
      !Array.isArray(body.messages) ||
      body.messages.length < 1 ||
      body.messages.length > 12
    ) {
      return jsonResponse({ error: "The chat history is invalid." }, 400);
    }

    const contents = [];
    for (const message of body.messages) {
      if (
        !message ||
        !["user", "assistant"].includes(message.role) ||
        typeof message.content !== "string" ||
        message.content.trim().length === 0 ||
        message.content.length > 4_000
      ) {
        return jsonResponse({ error: "A chat message is invalid." }, 400);
      }

      contents.push({
        role: message.role === "assistant" ? "model" : "user",
        parts: [{ text: message.content }],
      });
    }

    const language = body.language === "Tamil" ? "Tamil" : "English";
    const endpoint = new URL(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent",
    );

    try {
      const upstream = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": env.GEMINI_API_KEY,
        },
        body: JSON.stringify({
          systemInstruction: {
            parts: [
              {
                text: `You are JARVIS, a helpful assistant. Reply in ${language}.`,
              },
            ],
          },
          contents,
          generationConfig: { maxOutputTokens: 512 },
        }),
      });

      if (!upstream.ok) {
        console.error("Gemini request failed with status", upstream.status);
        return jsonResponse({ error: "The AI provider could not answer." }, 502);
      }

      const result = await upstream.json();
      const reply = result.candidates?.[0]?.content?.parts
        ?.map((part) => part.text || "")
        .join("")
        .trim();

      if (!reply) {
        return jsonResponse({ error: "The AI provider returned no reply." }, 502);
      }

      return jsonResponse({ reply });
    } catch (error) {
      console.error("Gemini request could not be completed", error);
      return jsonResponse({ error: "The AI provider could not be reached." }, 502);
    }
  },
};
