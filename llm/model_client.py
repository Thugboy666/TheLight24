import aiohttp
from llm.prompts_loader import get_system_prompt
from core.config import settings
from core.logger import logger

async def complete_text(prompt: str, max_tokens: int = 256, temperature: float = 0.7) -> str:
    url = settings.LLM_COMPLETION_URL
    system_prompt = get_system_prompt("system")
    payload = {
        "model": settings.LLM_MODEL,
        "prompt": f"{system_prompt}\n\n{prompt}",
        "max_tokens": max_tokens,
        "temperature": temperature,
    }

    logger.info("Calling LLM at %s", url)

    async with aiohttp.ClientSession() as session:
        async with session.post(url, json=payload, timeout=120) as resp:
            resp.raise_for_status()
            data = await resp.json()
            # adattare in base al server LLM (LM Studio, llama.cpp, ecc.)
            if "choices" in data and data["choices"]:
                return data["choices"][0].get("text", "").strip()
            return str(data)
