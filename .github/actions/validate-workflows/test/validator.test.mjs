import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import {
  loadWorkflow,
  validateCall,
  validateCallerFile,
  validateEmbeddedShells,
} from "../src/validate-workflows.mjs";

const actionRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sharedRoot = resolve(actionRoot, "../../..");
const fixtures = resolve(actionRoot, "test", "fixtures");

test("representative Karemo caller matches shared contracts", () => {
  validateCallerFile(resolve(fixtures, "callers", "karemo.yml"), sharedRoot, sharedRoot);
});

test("representative CVSmia caller matches shared contracts", () => {
  validateCallerFile(resolve(fixtures, "callers", "cvsmia.yml"), sharedRoot, sharedRoot);
});

test("rejects reusable workflow without workflow_call", () => {
  const contract = loadWorkflow(resolve(fixtures, "contracts", "missing-workflow-call.yml"));
  assert.throws(() => validateCall({ with: {} }, contract, "missing-trigger"), /does not expose on\.workflow_call/);
});

test("rejects renamed required input", () => {
  const contract = loadWorkflow(resolve(fixtures, "contracts", "required-input.yml"));
  const caller = loadWorkflow(resolve(fixtures, "invalid", "renamed-input.yml"));
  assert.throws(() => validateCall(caller.jobs.call, contract, "renamed-input"), /unknown input 'solution_path'/);
});

test("rejects missing required secret", () => {
  const contract = loadWorkflow(resolve(fixtures, "contracts", "required-secret.yml"));
  const caller = loadWorkflow(resolve(fixtures, "invalid", "missing-secret.yml"));
  assert.throws(() => validateCall(caller.jobs.call, contract, "missing-secret"), /omits required secret 'deployment_token'/);
});

test("rejects malformed embedded PowerShell", () => {
  const workflow = loadWorkflow(resolve(fixtures, "invalid", "malformed-powershell.yml"));
  assert.throws(() => validateEmbeddedShells(workflow, "malformed-powershell"), /invalid embedded pwsh/);
});

test("rejects malformed embedded Bash", () => {
  const workflow = loadWorkflow(resolve(fixtures, "invalid", "malformed-bash.yml"));
  assert.throws(() => validateEmbeddedShells(workflow, "malformed-bash"), /invalid embedded bash/);
});

test("rejects malformed workflow YAML", () => {
  assert.throws(() => loadWorkflow(resolve(fixtures, "invalid", "malformed-yaml.yml")), /invalid YAML/);
});
