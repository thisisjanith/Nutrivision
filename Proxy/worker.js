// Cloudflare Worker: thin proxy between NutriVision and the Claude API.
// Keeps the API key off the device and owns the prompt + JSON schema.
//
//   wrangler secret put ANTHROPIC_API_KEY
//   wrangler secret put APP_TOKEN        (same value as UserDefaults "proxyToken")
//   wrangler deploy
//
// Add rate limiting (Cloudflare rules) — APP_TOKEN alone is only a speed bump.

const MODEL = "claude-haiku-4-5-20251001";

const TOOL = {
  name: "report_food",
  description: "Report the food visible in the photo with nutrition estimates for the portion shown.",
  input_schema: {
    type: "object",
    properties: {
      food_name: { type: "string" },
      confidence_score: { type: "number", description: "0 to 1" },
      estimated_calories: { type: "number", description: "kcal for the portion shown" },
      macros: {
        type: "object",
        properties: { protein: { type: "number" }, carbs: { type: "number" }, fat: { type: "number" } },
        required: ["protein", "carbs", "fat"],
      },
      hidden_ingredients_flag: { type: "boolean", description: "true if glossy/oily texture etc. implies unseen fat or sugar" },
      hidden_ingredients_note: { type: "string" },
      portion: { type: "string", enum: ["small", "medium", "large", "cup", "tablespoon", "palm-sized"] },
    },
    required: ["food_name", "confidence_score", "estimated_calories", "macros", "hidden_ingredients_flag", "portion"],
  },
};

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
    if (env.APP_TOKEN && request.headers.get("X-App-Token") !== env.APP_TOKEN) {
      return new Response("Unauthorized", { status: 401 });
    }

    const { image_base64, media_type = "image/jpeg", distance_m } = await request.json();
    if (!image_base64 || image_base64.length > 4_000_000) return new Response("Bad image", { status: 400 });

    const hint = distance_m
      ? `The camera was about ${distance_m} m from the food (LiDAR). Use this with visible references (plate ~26 cm, fork, hand) to judge portion size.`
      : "Judge portion size from visible references such as the plate, fork or hand.";

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 400,
        tools: [TOOL],
        tool_choice: { type: "tool", name: "report_food" },
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type, data: image_base64 } },
            { type: "text", text: `Identify the main food and estimate its nutrition for the portion shown. ${hint} Pick the closest portion bucket. If unsure, lower confidence_score.` },
          ],
        }],
      }),
    });
    if (!upstream.ok) return new Response("Upstream error", { status: 502 });

    const result = await upstream.json();
    const call = result.content?.find((block) => block.type === "tool_use");
    if (!call) return new Response("No result", { status: 502 });
    return new Response(JSON.stringify(call.input), { headers: { "content-type": "application/json" } });
  },
};
