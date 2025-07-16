# ALOMA
**No infra. No no-code. Just code and let ALOMA handle the rest.**

ALOMA is a code-first workflow automation platform that lets you define automation logic in JavaScript, send data via JSON webhooks, and instantly deploy and test each step on our infrastructure.

## Getting Started

**Ready to try ALOMA? Start here:**

1. **See it in action** - Check out our [toy example](https://github.com/aloma-io/aloma-io/blob/main/docs/getting-started/toy-example.md) to understand how ALOMA works
2. **Choose your interface**:
   - **CLI**: [Install and use the CLI](https://github.com/aloma-io/aloma-io/blob/main/docs/CLI) for your preferred IDE
   - **Web UI**: [Use our web-based IDE](https://github.com/aloma-io/aloma-io/blob/main/docs/web-UI) in your browser
3. **Browse examples** - Explore our [library of workflows](https://github.com/aloma-io/aloma-io/tree/main/examples) you can deploy instantly

**[Complete Getting Started Guide](https://github.com/aloma-io/aloma-io/tree/main/docs/getting-started)**

## How It Works

ALOMA processes **tasks** (schemaless JSON payloads) through **steps** (JavaScript logic with matching conditions). When a task matches a step's conditions, the step executes and updates the task, potentially triggering downstream logic via **connectors** - reusable wrappers to external services.

**Key benefits:**
- **Automation-as-code** - Self-contained steps make debugging and maintenance easy
- **Scalable complexity** - Adding the 100th step is as easy as adding the first
- **Built for developers** - Code in JavaScript, deploy instantly, test immediately
- **Robust platform** - Automatic scaling with parallel processing and exception handling

## What You Can Build

- **AI Agents** - Intelligent automation with decision-making logic
- **Data Pipelines** - Transform and route data between systems  
- **Application Integrations** - Connect services and automate workflows
- **Any workflow** where data can be sent as JSON and logic can be expressed in code

## Documentation & Resources

- **[Complete Documentation](https://github.com/aloma-io/aloma-io/tree/main/docs)** - Full user guide including CLI documentation
- **[Example Workflows](https://github.com/aloma-io/aloma-io/tree/main/examples)** - Ready-to-deploy workflows for your workspace
- **[Connector SDK](https://github.com/aloma-io/connectors)** - Build on-premises connectors for your environment
- **Request new cloud connectors** - Email us at connector-request@aloma.io

## Why Choose ALOMA Over No-Code Tools?

Unlike tools like n8n, ALOMA's code-first approach means:
- **Easier debugging** - Standard JavaScript debugging tools work
- **Better maintainability** - Code is self-documenting and version-controllable  
- **Unlimited complexity** - No visual workflow limitations
- **Developer-friendly** - Use your existing skills and tools

