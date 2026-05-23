FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir "fastmcp>=2" openai google-genai httpx

COPY braintrust_mcp.py .

# Most cloud platforms inject a PORT env var. The server reads BRAINTRUST_PORT,
# so map one to the other at start. Falls back to 8787 locally.
ENV BRAINTRUST_PORT=8787
CMD ["sh", "-c", "BRAINTRUST_PORT=${PORT:-8787} python braintrust_mcp.py"]
