# ALOMA

**No infra. No no-code. Just code and let ALOMA handle the rest.**

---

## Overview

ALOMA is a code-first workflow automation platform.

Define your automation logic in **coded JavaScript** steps. Send data to ALOMA in **JSON** using Webhooks or API calls. Build your workflows step-by-step by **instantly deploying and testing** each step on our infrastructure.

Use with the **CLI** to edit in your own IDE, or use our **web-based IDE** in the UI.

**Tasks**, which are schemaless JSON payloads (including files), are streamed into your Aloma workspaces. ALOMA continuously evaluates the tasks against available steps and executes those that match; each **step** containing matching conditions and a block of JavaScript logic. The task is continuously updated after step execution, triggering downstream logic as needed by invoking **connectors** - authorised, reusable wrappers to external services. 

**Automation-as-code**, self-contained steps structured with IDE, makes debugging and maintenance easy - especially as compared to no-code tools like n8n. It also makes it easy to build long, complex workflows with many paths, as the conditions in the step controls when it is triggered. Adding the 100th step to a workflow is as easy as adding the first.

Use ALOMA to build your AI Agents, pipelines, application integrations - any workflow where data can be sent to ALOMA in JSON logic, can be expressed in code, and can trigger services that can be reached by our connectors.

The ALOMA platform is robust and automatically scales to handle your workloads. Tasks are processed in parallel, with built in exception handling.


## Documentation

The general user documentation for ALOMA, is located under the docs directory [docs directory](https://github.com/aloma-io/aloma-io/tree/main/docs) of the present repo here including for the CLI.

There is a growing [library of workflows with steps](https://github.com/aloma-io/aloma-io/tree/main/examples) that can be deployed to your ALOMA workspace via the CLI as per instructions. Please feel free to share your steps here for the community.

There is a [connector repo](https://github.com/aloma-io/connectors) with an SDK to build an on prem connector for your local environment and several example connectors.

Please send requests for new cloud connectors to us here at connector-request@aloma.io.


## Getting Started

Check out the [toy example](https://github.com/aloma-io/aloma-io/blob/main/docs/getting-started/toy-example.md) to understand the basics of how ALOMA works. 

You can access ALOMA either using CLI  or Web UI .

- [CLI Documentation](https://github.com/aloma-io/aloma-io/blob/main/docs/CLI)
- [Web UI Documentation](https://github.com/aloma-io/aloma-io/blob/main/docs/web-UI)

---

## Next Steps

Now that you've set up and deployed the Hubspot connector with example steps to get contacts and get companies, you can start automating with ALOMA.

- [Access ALOMA getting started documentation](https://github.com/aloma-io/aloma-io/tree/main/docs/getting-started)
- [Watch the Toy getting started video and documentation](https://github.com/aloma-io/aloma-io/blob/main/docs/getting-started/toy-example.md)
- [Read documentation for the Hubspot Example](https://github.com/aloma-io/aloma-io/tree/main/examples/hubspot)
- [Access more example workflows](https://github.com/aloma-io/aloma-io/tree/main/examples)
- Join the community (coming soon!)

