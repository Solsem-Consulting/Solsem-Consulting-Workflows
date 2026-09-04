import { existsSync, readFileSync, readdirSync } from "node:fs";
import { resolve, relative } from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { parseDocument } from "yaml";

const sharedWorkflowPattern = /^Solsem-Consulting\/Solsem-Consulting-Workflows\/\.github\/workflows\/(?<file>[^@]+\.ya?ml)@[0-9a-fA-F]{40}$/;
const localWorkflowPattern = /^\.\/\.github\/workflows\/(?<file>.+\.ya?ml)$/;

export function loadWorkflow(path) {
  const document = parseDocument(readFileSync(path, "utf8"), {
    prettyErrors: true,
    uniqueKeys: true,
  });
  if (document.errors.length > 0) {
    throw new Error(`${path}: invalid YAML: ${document.errors.map((error) => error.message).join("; ")}`);
  }
  return document.toJS() ?? {};
}

function workflowCallContract(workflow, label) {
  const triggers = workflow.on;
  if (!triggers || typeof triggers !== "object" || !("workflow_call" in triggers)) {
    throw new Error(`${label}: referenced workflow does not expose on.workflow_call`);
  }
  return triggers.workflow_call ?? {};
}

export function validateCall(job, contractWorkflow, label) {
  const contract = workflowCallContract(contractWorkflow, label);
  const declaredInputs = contract.inputs ?? {};
  const providedInputs = job.with ?? {};

  for (const input of Object.keys(providedInputs)) {
    if (!(input in declaredInputs)) {
      throw new Error(`${label}: caller passes unknown input '${input}'`);
    }
  }
  for (const [input, definition] of Object.entries(declaredInputs)) {
    const hasDefault = definition && typeof definition === "object" && "default" in definition;
    if (definition?.required === true && !hasDefault && !(input in providedInputs)) {
      throw new Error(`${label}: caller omits required input '${input}'`);
    }
  }

  const declaredSecrets = contract.secrets ?? {};
  if (job.secrets === "inherit") {
    return;
  }
  const providedSecrets = job.secrets ?? {};
  for (const secret of Object.keys(providedSecrets)) {
    if (!(secret in declaredSecrets)) {
      throw new Error(`${label}: caller passes unknown secret '${secret}'`);
    }
  }
  for (const [secret, definition] of Object.entries(declaredSecrets)) {
    if (definition?.required === true && !(secret in providedSecrets)) {
      throw new Error(`${label}: caller omits required secret '${secret}'`);
    }
  }
}

function resolveContract(uses, repositoryRoot, sharedRoot) {
  const sharedMatch = uses.match(sharedWorkflowPattern);
  if (sharedMatch) {
    return resolve(sharedRoot, ".github", "workflows", sharedMatch.groups.file);
  }

  const localMatch = uses.match(localWorkflowPattern);
  if (!localMatch) {
    return null;
  }
  const localPath = resolve(repositoryRoot, ".github", "workflows", localMatch.groups.file);
  if (existsSync(localPath)) {
    return localPath;
  }
  const sharedPath = resolve(sharedRoot, ".github", "workflows", localMatch.groups.file);
  return existsSync(sharedPath) ? sharedPath : localPath;
}

export function validateCallerFile(callerPath, repositoryRoot, sharedRoot) {
  const caller = loadWorkflow(callerPath);
  for (const [jobName, job] of Object.entries(caller.jobs ?? {})) {
    if (!job || typeof job !== "object" || typeof job.uses !== "string") {
      continue;
    }
    const contractPath = resolveContract(job.uses, repositoryRoot, sharedRoot);
    if (!contractPath) {
      continue;
    }
    if (!existsSync(contractPath)) {
      throw new Error(`${callerPath}:${jobName}: referenced workflow not found: ${contractPath}`);
    }
    validateCall(job, loadWorkflow(contractPath), `${callerPath}:${jobName}`);
  }
}

function normalizedScript(script, shell) {
  const replacement = shell === "pwsh" ? "$true" : "EXPRESSION";
  return script.replace(/\$\{\{[\s\S]*?\}\}/g, replacement);
}

function validateScript(script, shell, label) {
  const normalized = normalizedScript(script, shell);
  const result = shell === "pwsh"
    ? spawnSync(
        "pwsh",
        ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "$code = [Console]::In.ReadToEnd(); [void][scriptblock]::Create($code)"],
        { input: normalized, encoding: "utf8", timeout: 15_000 },
      )
    : spawnSync("bash", ["-n"], { input: normalized, encoding: "utf8", timeout: 15_000 });

  if (result.error) {
    throw new Error(`${label}: could not start ${shell}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const diagnostic = (result.stderr || result.stdout || "syntax error").trim();
    throw new Error(`${label}: invalid embedded ${shell}: ${diagnostic}`);
  }
}

export function validateEmbeddedShells(workflow, label) {
  for (const [jobName, job] of Object.entries(workflow.jobs ?? {})) {
    if (!job || typeof job !== "object" || !Array.isArray(job.steps)) {
      continue;
    }
    const runner = String(job["runs-on"] ?? "").toLowerCase();
    const jobDefault = job.defaults?.run?.shell;
    const workflowDefault = workflow.defaults?.run?.shell;
    for (const [index, step] of job.steps.entries()) {
      if (!step || typeof step !== "object" || typeof step.run !== "string") {
        continue;
      }
      const configuredShell = String(step.shell ?? jobDefault ?? workflowDefault ?? "").toLowerCase();
      const shell = configuredShell.includes("pwsh") || configuredShell.includes("powershell") || (!configuredShell && runner.includes("windows"))
        ? "pwsh"
        : "bash";
      validateScript(step.run, shell, `${label}:${jobName}:step-${index + 1}`);
    }
  }
}

function workflowFiles(repositoryRoot) {
  const directory = resolve(repositoryRoot, ".github", "workflows");
  return readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile() && /\.ya?ml$/i.test(entry.name))
    .map((entry) => resolve(directory, entry.name));
}

export function validateRepository(repositoryRoot, sharedRoot, product = "none") {
  const files = workflowFiles(repositoryRoot);
  for (const file of files) {
    const workflow = loadWorkflow(file);
    validateEmbeddedShells(workflow, relative(repositoryRoot, file));
  }

  if (product !== "none") {
    if (!new Set(["karemo", "cvsmia"]).has(product)) {
      throw new Error(`Unsupported product contract '${product}'`);
    }
    validateCallerFile(resolve(repositoryRoot, ".github", "workflows", "publish.yml"), repositoryRoot, sharedRoot);
  }

  return files.length;
}

function option(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) {
    throw new Error(`Missing ${name}`);
  }
  return process.argv[index + 1];
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const repositoryRoot = resolve(option("--repository-root"));
  const sharedRoot = resolve(option("--shared-root"));
  const product = option("--product");
  const count = validateRepository(repositoryRoot, sharedRoot, product);
  console.log(`Workflow contract validation passed for ${count} workflow file(s).`);
}
