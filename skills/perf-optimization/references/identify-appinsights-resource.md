# Identify application insights resource of the current project

## Overview

Find out the application insights resources to focus on. Follow the steps below **in order** — stop as soon as a resource is confirmed.

## Steps

### 1. Check investigation notes

Check whether `investigation-notes.md` exists in the working directory. If it does, read it and look for an existing Application Insights resource (resource ID, app ID, subscription, resource group).

- If values are found, present them to the user and ask: **"I found these Application Insights details from a previous investigation. Do you want to continue with this resource, or use a different one?"**
- If the user confirms, use the existing values and skip the remaining steps.
- If the user declines, continue to the next steps and update the notes afterward.

### 2. Quick check

* Check the source code quickly to see if there are any hints to an application insights resource (e.g., connection strings, instrumentation keys, resource IDs in config files or environment variables).
* Ask the user to confirm if the found ones are the ones to use.

### 3. Ask the user

* Ask the user to provide the application insights resource directly.

### 4. Write investigation notes

After the resource is confirmed (from any step above), write or update `investigation-notes.md` in the working directory. See [Investigation Notes](../../shared/investigation-notes.md) for the file format and rules.

