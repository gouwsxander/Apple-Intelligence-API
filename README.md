# Apple Intelligence Web API

A Swift-based web API that exposes Apple's on-device Foundation Models through an OpenAI-compatible HTTP interface. Built with Vapor and designed to run on Apple Intelligence-enabled devices.

## Features

- [X] **OpenAI-compatible:** Works with existing OpenAI/OpenRouter client libraries
- [X] **Non-chat completions:** Single-prompt responses
- [X] **Chat completions:** Multi-turn conversations with context
- [X] **Streaming responses:** Real-time token streaming via Server-Sent Events
- [X] **Multiple models:** Base and permissive content guardrails
- [ ] **Authentication**
- [ ] **Structured outputs**
- [ ] **Tool/function calling**
- [ ] **Tests**

## Running the server

Requirements:
- [Apple Intelligence](https://support.apple.com/en-ca/121115)-enabled device
- Swift 6.0+

Build the project:
```bash
swift build
```

Run the server:
```bash
swift run AppleIntelligenceApi serve [--hostname, -H] [--port, -p] [--bind, -b] [--unix-socket]
```

The API will be available at `http://localhost:8080` by default.

### Troubleshooting
Port already in use:
```bash
lsof -i :8080  # Find out what's using the port
swift run AppleIntelligenceApi serve -p 9000  # Use a different port if needed
```

Apple Intelligence not available:
- Make sure it's enabled: Settings --> Apple Intelligence & Siri
- Check your device is [supported](https://support.apple.com/en-ca/121115)

## Usage

This API follows the same standard as OpenAI and OpenRouter, so it should be straightforward to adopt.

For completeness, here are some examples...

### Using cURL

Chat completion:
```bash
curl http://localhost:8080/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "base",
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ]
  }'
```

Streaming Response:
```bash
curl http://localhost:8080/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "base",
    "messages": [
      {"role": "user", "content": "Tell me a story"}
    ],
    "stream": true
  }'
```

### Using Python
```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8080/api/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="base",
    messages=[
        {"role": "user", "content": "Hello!"}
    ]
)

print(response.choices[0].message.content)
```

### Using JavaScript/TypeScript
```typescript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'http://localhost:8080/api/v1',
  apiKey: 'not-needed'
});

const response = await client.chat.completions.create({
  model: 'base',
  messages: [{ role: 'user', content: 'Hello!' }],
  stream: true
});

for await (const chunk of response) {
  process.stdout.write(chunk.choices[0]?.delta?.content || '');
}
```

### API reference

For a complete breakdown of how to use the API, I suggest looking at the [OpenAI](https://platform.openai.com/docs/api-reference/chat) or [OpenRouter](https://openrouter.ai/docs/api/reference/overview) documentation.

Our API differs in a few key places:
- Available models: `base` (default guardrails) and `permissive` (relaxed filtering)
- Runs server on-device (so no API key needed)
- Not all features are available!

## Development

### Running tests

We currently do not have any tests! If you would like to implement some, please make a PR.

```bash
swift test
```

### Project structure

- `./Sources/routes.swift`: API route definition
- `./Sources/Utils/AbortErrors.swift`: Error type definitions
- `./Sources/Utils/RequestContent.swift`: Parsing incoming requests
- `./Sources/Utils/ResponseSession.swift`: Foundation models interface
- `./Sources/Utils/ResponseGenerator.swift`: Generates responses

### Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a pull request

## Cloud inference
I currently do not plan to offer cloud inference for this API.

If you want to use the server on your local network, you can run the server from any Apple Intelligence-enabled device.

If you want cloud inference, you will probably want a VPS. Of course, this VPS needs to be on Apple Intelligence-enabled hardware; HostMyApple and MacInCloud seem reasonable.

## Acknowledgments

- Built with [Vapor](https://vapor.codes) web framework
- Uses Apple's [Foundation Models Framework](https://developer.apple.com/documentation/FoundationModels)
- OpenAI-compatible API design based on [OpenRouter](https://openrouter.ai/docs/quickstart)

## Disclaimer

This is an unofficial API wrapper for Apple Intelligence. It is not affiliated with or endorsed by Apple Inc. Use responsibly and in accordance with Apple's terms of service.
