import yaml from 'js-yaml';

interface WorkflowStep {
  id: number | string;
  name?: string;
  call: string;
  deps?: (number | string)[];
  input_template?: Record<string, unknown>;
  capture_as?: string;
}

interface Workflow {
  name: string;
  version?: string;
  description?: string;
  steps: WorkflowStep[];
}

/**
 * Convert a workflow YAML string into a Mermaid flowchart definition.
 */
export function workflowToMermaid(yamlString: string): string {
  const workflow = yaml.load(yamlString) as Workflow;

  if (!workflow?.steps?.length) {
    return 'flowchart TD\n  empty["No steps defined"]';
  }

  const lines: string[] = ['flowchart TD'];
  const stepIds = new Set(workflow.steps.map(s => s.id));

  // Add nodes with labels
  for (const step of workflow.steps) {
    const callLabel = step.call.replace(/[._]/g, ' ');
    const safeId = String(step.id).replace(/[^a-zA-Z0-9_]/g, '_');
    const label = step.name ? `${step.id}: ${step.name}` : String(step.id);
    lines.push(`  ${safeId}["<b>${label}</b><br/>${callLabel}"]`);
  }

  lines.push('');

  // Add edges based on deps
  for (const step of workflow.steps) {
    const safeId = String(step.id).replace(/[^a-zA-Z0-9_]/g, '_');
    if (step.deps?.length) {
      for (const dep of step.deps) {
        if (stepIds.has(dep)) {
          const safeDep = String(dep).replace(/[^a-zA-Z0-9_]/g, '_');
          lines.push(`  ${safeDep} --> ${safeId}`);
        }
      }
    }
  }

  lines.push('');

  // Style start nodes (no deps) with green
  const starters = workflow.steps.filter(s => !s.deps?.length);
  for (const s of starters) {
    const safeId = String(s.id).replace(/[^a-zA-Z0-9_]/g, '_');
    lines.push(`  style ${safeId} fill:#c8e6c9,stroke:#43a047`);
  }

  // Style end nodes (not depended on by anyone) with blue
  const depsSet = new Set(workflow.steps.flatMap(s => s.deps || []));
  const enders = workflow.steps.filter(s => !depsSet.has(s.id));
  for (const s of enders) {
    const safeId = String(s.id).replace(/[^a-zA-Z0-9_]/g, '_');
    // Don't override green if it's also a starter
    if (starters.includes(s)) continue;
    lines.push(`  style ${safeId} fill:#bbdefb,stroke:#1976d2`);
  }

  return lines.join('\n');
}
