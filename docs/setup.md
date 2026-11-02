# Setup guide

These steps take about 30–60 minutes for a GHES administrator plus an org owner. Placeholders:

| Placeholder | Meaning |
|---|---|
| `ghes.example.com` | Your GHES hostname |
| `YOUR-ORG` | Organization that hosts the shared workflows |
| `copilot-agent` | Bot user that the agents act as (any name works) |

## 1. Enable the copilot-proxy on GHES

The Copilot CLI's offline mode sends model requests to `https://<ghes>/_copilot_proxy`. GHES forwards
them to an OpenAI-compatible endpoint you control, such as Azure OpenAI / Microsoft Foundry.

> The copilot-proxy is a preview feature of GitHub Enterprise Server. Check the release notes of your
> GHES version for availability and the exact settings before you rely on it.

From the administrative shell (`ssh -p 122 admin@ghes.example.com`):

```bash
ghe-config app.copilot-proxy.enabled true
ghe-config app.copilot-proxy.endpoint-url 'https://YOUR-RESOURCE.openai.azure.com/openai/v1'
ghe-config secrets.copilot-proxy.endpoint-key 'YOUR-API-KEY'
ghe-config app.copilot-proxy.provider-type openai
ghe-config app.copilot-proxy.provider-wire-api completions
ghe-config app.copilot-proxy.provider-model-id 'gpt-5.4'      # model name shown to users
ghe-config app.copilot-proxy.provider-wire-model 'gpt-5.4'    # deployment/model name sent upstream
ghe-config app.copilot-proxy.upstream-timeout 300
ghe-config-apply
```

Check it from any machine that trusts the GHES certificate:

```bash
curl -s -H "Authorization: Bearer $GHES_TOKEN" https://ghes.example.com/_copilot_proxy/models | jq .
```

## 2. Prepare a self-hosted runner

Any Linux runner registered with your GHES works. On Ubuntu:

```bash
# Register the runner as usual, and give it the label "copilot-agent".
sudo ./scripts/setup-runner.sh --runner-dir /home/runner/actions-runner \
  --ca-cert ./ghes-ca.crt    # only if GHES uses a private/self-signed CA
```

The script installs git, jq, curl, GitHub CLI, Node.js 22 and `@github/copilot`. It also adds the CA to the system trust store.

> Use a dedicated runner pool (ephemeral runners are best). The agent can run arbitrary shell commands
> inside the job, so treat the runner like any CI machine that executes untrusted code.

## 3. Create the bot user and its token

1. Create a GHES user, for example `copilot-agent`, and add it to the organization(s) that will use the agents.
2. Give it write access to the target repositories (a team works well).
3. Sign in as the bot and create a **personal access token (classic)** with scopes `repo`, `workflow`, `read:org`.
4. Store the token as an **organization secret** named `COPILOT_AGENT_TOKEN`, available to the repositories that use the agents.

The same token pushes branches, opens pull requests, posts reviews, and authenticates to the copilot-proxy.

## 4. Import this repository into GHES

```bash
git clone https://github.com/mvanderbend-msoft/copilot-cli-ghes-cloud-agents.git
cd copilot-cli-ghes-cloud-agents
git remote set-url origin https://ghes.example.com/YOUR-ORG/copilot-cli-ghes-cloud-agents.git
git push -u origin main
```

Then, in that repository on GHES, go to **Settings → Actions → General → Access** and choose
**"Accessible from repositories in the YOUR-ORG organization"**. Without this, other repositories
can't call the reusable workflows.

## 5. (Optional) Smoke test

Copy `templates/copilot-smoke-test.yml` into a test repository as `.github/workflows/copilot-smoke-test.yml`.
Then run it from the Actions tab. It should print the tool versions and `copilot-proxy OK`.

## 6. Enable the agents in a repository

1. Copy `templates/copilot.yml` to `.github/workflows/copilot.yml`.
2. Replace `YOUR-ORG`, and replace `copilot-agent` if your bot has another login (it appears twice).
3. Create a `copilot` label in the repository.
4. Optionally add `.github/copilot-instructions.md` and custom agents in `.github/agents/`. See `examples/`.

Now open an issue, describe a small change, and add the `copilot` label.

## Workflow inputs

Both reusable workflows accept these inputs:

| Input | Default | Description |
|---|---|---|
| `runner-label` | `copilot-agent` | Label of the self-hosted runner pool |
| `model` | *(proxy default)* | Model override |
| `default-agent` | *(built-in)* | Custom agent to use when the trigger doesn't name one |
| `timeout-minutes` | `45` | Coding agent only |
| `bot-login` | `copilot-agent` | Coding agent only; the bot's own comments are ignored |
| `trigger-label` | `copilot` | Review agent only; this label is removed after the review |
