# Standard Skill Preamble

Standard workflow steps that every skill should follow at the beginning of execution. These steps ensure the agent checks for existing investigation context before asking the user for new inputs.

## 1. Check investigation notes

Before asking the user for inputs, check whether `investigation-notes.md` exists in the working directory. If it does, read it for existing Application Insights details (especially **App ID** and **Resource ID**). See [Investigation Notes](investigation-notes.md) for the file format and rules.

- If an **App ID** is found, present it to the user and ask whether to reuse it or provide a different one.
- If only a **Resource ID** is found (no App ID), resolve the App ID by running the script in [resolve-app-id.md](resolve-app-id.md), then confirm with the user.
- If the user confirms, skip asking for the App ID in the next step.

## 2. Gather inputs

Ask the user for any values not already obtained from the investigation notes:

- **App ID**: The Application Insights app ID (GUID). If the user provides a resource ID instead, resolve it by running the script in [resolve-app-id.md](resolve-app-id.md).
- *(Additional skill-specific inputs — each skill adds its own required values here.)*

After all inputs are confirmed, **write or update `investigation-notes.md`** with the App ID and any other resolved values (Resource ID, Subscription ID, Resource Group). See [Investigation Notes](investigation-notes.md).
