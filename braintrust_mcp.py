"""
Braintrust MCP server.

Exposes GPT and Gemini to Claude chat as candid-critique tools, modelled on
Pixar's Braintrust: honest feedback, no authority over the work, problem-focused,
no prescriptive mandates. Run on your own box, expose over your Cloudflare Tunnel,
and add as a custom connector in Claude.

  pip install "fastmcp>=2" openai google-genai
  export OPENAI_API_KEY=sk-...
  export GEMINI_API_KEY=...
  # optional, but recommended if the endpoint is reachable from the public internet:
  export BRAINTRUST_TOKEN=some-long-random-string
  python braintrust_mcp.py

Then point your tunnel at http://localhost:8787/mcp and add that URL as a
custom connector. If you set BRAINTRUST_TOKEN, Claude's connector config needs
the same value as a Bearer token (or just gate the hostname behind Cloudflare
Access, which is cleaner).
"""

import asyncio
import os

import httpx
from fastmcp import FastMCP
from openai import AsyncOpenAI
from google import genai

# --- config (all overridable via env so you can bump models without editing code) ---
OPENAI_MODEL = os.environ.get("BRAINTRUST_OPENAI_MODEL", "gpt-5.5")
GEMINI_MODEL = os.environ.get("BRAINTRUST_GEMINI_MODEL", "gemini-3.1-pro-preview")
PORT = int(os.environ.get("BRAINTRUST_PORT", "8787"))
AUTH_TOKEN = os.environ.get("BRAINTRUST_TOKEN")  # if unset, no bearer check
# Optional. If unset, the check_ai_detection tool reports "not configured" rather
# than crashing the server — so you can deploy before subscribing to GPTZero.
GPTZERO_API_KEY = os.environ.get("GPTZERO_API_KEY")

openai_client = AsyncOpenAI()  # reads OPENAI_API_KEY
gemini_client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

# The Braintrust framing. The point isn't praise — it's surfacing what the other
# reviewers (including Claude) might miss. Candour over comfort, problem over person.
BRAINTRUST_SYSTEM = (
    "You are a member of a Braintrust giving feedback in the Pixar tradition. "
    "Your job is to make the work better by being genuinely candid, not kind for its "
    "own sake. You have no authority over the work and you are not prescribing fixes — "
    "you are diagnosing what isn't working and why, so the author can decide. "
    "Rules: (1) Lead with the most serious problems, not the easy ones. "
    "(2) Be specific and concrete; point to the exact passage, claim, or decision. "
    "(3) Separate the problem from the person — critique the work, never the author. "
    "(4) Do not soften with reflexive praise or hedging; if something is genuinely "
    "strong, say so briefly and move on. (5) Name your blind spots — flag where you're "
    "uncertain or where a domain expert should check you. (6) No sycophancy. If the work "
    "is good, the most useful thing you can do is find the one thing that would make it "
    "great. Assume two other capable reviewers are looking at this too; prioritise what "
    "they're likely to overlook."
)


async def _ask_gpt(work: str, context: str) -> str:
    user = f"WORK TO CRITIQUE:\n{work}"
    if context:
        user += f"\n\nCONTEXT FROM THE AUTHOR:\n{context}"
    resp = await openai_client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=[
            {"role": "system", "content": BRAINTRUST_SYSTEM},
            {"role": "user", "content": user},
        ],
    )
    return resp.choices[0].message.content or "(empty response)"


async def _ask_gemini(work: str, context: str) -> str:
    user = f"WORK TO CRITIQUE:\n{work}"
    if context:
        user += f"\n\nCONTEXT FROM THE AUTHOR:\n{context}"
    resp = await asyncio.to_thread(
        gemini_client.models.generate_content,
        model=GEMINI_MODEL,
        contents=user,
        config={"system_instruction": BRAINTRUST_SYSTEM},
    )
    return resp.text or "(empty response)"


# Optional bearer-token gate. If BRAINTRUST_TOKEN is set, the endpoint requires it.
# In FastMCP 3.x the verifier goes on the constructor, not on run().
_auth = None
if AUTH_TOKEN:
    from fastmcp.server.auth import StaticTokenVerifier

    _auth = StaticTokenVerifier(tokens={AUTH_TOKEN: {"client_id": "braintrust"}})

mcp = FastMCP("braintrust", auth=_auth)


@mcp.tool
async def ask_gpt(work: str, context: str = "") -> str:
    """Get candid Braintrust-style critique of a piece of work from GPT.

    Args:
        work: The text to critique (draft, abstract, argument, plan, etc.).
        context: Optional author notes — goal, audience, what you're unsure about.
    """
    return await _ask_gpt(work, context)


@mcp.tool
async def ask_gemini(work: str, context: str = "") -> str:
    """Get candid Braintrust-style critique of a piece of work from Gemini.

    Args:
        work: The text to critique (draft, abstract, argument, plan, etc.).
        context: Optional author notes — goal, audience, what you're unsure about.
    """
    return await _ask_gemini(work, context)


@mcp.tool
async def braintrust(work: str, context: str = "") -> str:
    """Convene the full Braintrust: get critique from BOTH GPT and Gemini in parallel.

    Returns both reviews labelled separately so they can be compared against each
    other (and against Claude's own read). Use this when you want the widest net
    for blind spots on a single piece of work.

    Args:
        work: The text to critique (draft, abstract, argument, plan, etc.).
        context: Optional author notes — goal, audience, what you're unsure about.
    """
    gpt_review, gemini_review = await asyncio.gather(
        _ask_gpt(work, context),
        _ask_gemini(work, context),
        return_exceptions=True,
    )

    def fmt(name, model, result):
        if isinstance(result, Exception):
            return f"### {name} ({model}) — ERROR\n{type(result).__name__}: {result}"
        return f"### {name} ({model})\n{result}"

    return (
        fmt("GPT", OPENAI_MODEL, gpt_review)
        + "\n\n---\n\n"
        + fmt("Gemini", GEMINI_MODEL, gemini_review)
    )


@mcp.tool
async def check_ai_detection(text: str) -> str:
    """Score how AI-generated a piece of text reads, via GPTZero.

    This is a DETECTOR, not a critic — separate from the braintrust. Useful for
    sanity-checking a draft before submission, since journals increasingly screen
    for this. GPTZero truncates input at ~50,000 characters.

    Args:
        text: The text to analyse.
    """
    if not GPTZERO_API_KEY:
        return (
            "GPTZero is not configured. Set the GPTZERO_API_KEY secret "
            "(fly secrets set GPTZERO_API_KEY=...) and redeploy to enable this tool."
        )

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            r = await client.post(
                "https://api.gptzero.me/v2/predict/text",
                headers={
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "x-api-key": GPTZERO_API_KEY,
                },
                json={"document": text, "multilingual": False},
            )
            r.raise_for_status()
            data = r.json()
    except Exception as e:
        return f"GPTZero request failed: {type(e).__name__}: {e}"

    docs = data.get("documents") or []
    if not docs:
        return f"Unexpected GPTZero response shape:\n{data}"

    d = docs[0]
    probs = d.get("class_probabilities", {})
    lines = [
        f"Predicted class: {d.get('predicted_class', 'unknown')}",
        f"Confidence: {d.get('confidence_category', 'unknown')}",
    ]
    if probs:
        lines.append(
            "Probabilities — "
            f"human {probs.get('human', '?')}, "
            f"AI {probs.get('ai', '?')}, "
            f"mixed {probs.get('mixed', '?')}"
        )
    if d.get("average_generated_prob") is not None:
        lines.append(f"Average generated prob: {d['average_generated_prob']}")
    lines.append(
        "\nNote: AI-detection scores are probabilistic and not definitive — "
        "treat as one signal, not a verdict."
    )
    return "\n".join(lines)


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=PORT, path="/mcp")
