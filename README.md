# TurtleAI — Groq Adaptation

> **This is a fork of [gotoundo/TurtleAI](https://github.com/gotoundo/TurtleAI), adapted to use [Groq](https://groq.com/) instead of Gemini as the LLM backend. All credit for the original project goes to gotoundo.**

## Why Groq?

Groq runs on dedicated LPU hardware, making it extremely fast — great for real-time turtle control in Minecraft. It's free to use (with rate limits) and doesn't require any local setup. You just need a free API key from [console.groq.com](https://console.groq.com).

## Getting Started

Get a free Groq API key from [console.groq.com](https://console.groq.com) and run this script on your in-game Computer to download the Groq chatbot with documentation, and the client for controlling turtles:

```lua
wget run https://raw.githubusercontent.com/Pazko77/TurtleAI/refs/heads/main/download_turtle_ai_client.lua
```

Then download and run this turtle server setup script on a turtle you want to control:

```lua
wget run https://raw.githubusercontent.com/Pazko77/TurtleAI/refs/heads/main/download_turtle_ai_server.lua
```



