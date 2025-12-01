import React from 'react';
import ReactFlow, { Background, Controls, MiniMap, addEdge, Connection, Edge, Node, useNodesState, useEdgesState } from 'reactflow';
import 'reactflow/dist/style.css';
import { Alert, Autocomplete, Box, Button, Divider, Grid2 as Grid, IconButton, LinearProgress, Paper, Stack, TextField, Tooltip, Typography, Dialog, DialogTitle, DialogContent, DialogActions, MenuItem, Chip, Snackbar, Tabs, Tab, useTheme, GlobalStyles } from '@mui/material';
import CloseIcon from '@mui/icons-material/Close';
import SaveIcon from '@mui/icons-material/Save';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import VisibilityIcon from '@mui/icons-material/Visibility';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import TaskAltIcon from '@mui/icons-material/TaskAlt';
import AddBoxIcon from '@mui/icons-material/AddBox';
import AccountTreeIcon from '@mui/icons-material/AccountTree';
import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import { useNavigate, useParams } from 'react-router-dom';
import { useThinkPrompts, useThinkWorkflowRead, useRules } from '../../api';
import { thinkWorkflowCreateGraph, thinkWorkflowUpdateGraph, thinkWorkflowValidateGraph } from '../../thinkApi';
import YAML from 'js-yaml';
import Viewer from '../../components/Viewer';
import WorkflowDiagram from '../../components/WorkflowDiagram';
import { workflowToMermaid } from '../../utils/workflowToMermaid';

const PANEL_HEIGHT = 'calc(100vh - 260px)';

type RFNode = Node<{ id: number; name: string; call: string; input_template?: any; capture_as?: string; label?: string }>;

function defaultGraph(): { nodes: RFNode[]; edges: Edge[] } {
  const nodes: RFNode[] = [
    { id: '1', position: { x: 120, y: 120 }, data: { id: 1, name: 'start', call: 'prompt_say', input_template: { text: 'Start' }, label: '1 start' }, type: 'default' },
    { id: '2', position: { x: 120, y: 240 }, data: { id: 2, name: 'done', call: 'prompt_say', input_template: { text: 'Done' }, label: '2 done' }, type: 'default' }
  ];
  const edges: Edge[] = [{ id: 'e1-2', source: '1', target: '2' }];
  return { nodes, edges };
}

function slugifyName(name: string): string {
  return (name || '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .replace(/_{2,}/g, '_');
}

function cleanRules(list?: string[]) {
  return (list || []).map((r) => r?.trim() || '').filter(Boolean);
}

function toGraphPayload(nodes: RFNode[], edges: Edge[], description?: string, driverVersion?: string, name?: string, rules?: string[], version?: number) {
  return {
    description: description || '',
    driver_version: driverVersion || 'stable',
    name: name || '',
    rules: cleanRules(rules),
    version: version || 1,
    nodes: nodes.map(n => ({ id: n.data.id, name: n.data.name, call: n.data.call, input_template: n.data.input_template, capture_as: n.data.capture_as })),
    edges: edges.map(e => ({ source: e.source, target: e.target }))
  };
}

function toYamlPreview(nodes: RFNode[], edges: Edge[], id: string, description?: string, driverVersion?: string, name?: string, rules?: string[], version?: number) {
  const ids = nodes.map(n => n.id);
  const indeg: Record<string, number> = {}; ids.forEach(i => indeg[i] = 0);
  const adj: Record<string, string[]> = {};
  const depsMap: Record<string, string[]> = {};
  ids.forEach(i => depsMap[i] = []);
  edges.forEach(e => {
    if (e.source && e.target) {
      indeg[e.target] = (indeg[e.target] || 0) + 1;
      (adj[e.source] ||= []).push(e.target);
      if (!depsMap[e.target].includes(e.source)) depsMap[e.target].push(e.source);
    }
  });
  const q = ids.filter(i => (indeg[i] || 0) === 0);
  const order: string[] = [];
  while (q.length) { const u = q.shift()!; order.push(u); (adj[u] || []).forEach(v => { indeg[v]--; if (indeg[v] === 0) q.push(v); }); }
  const map: Record<string, RFNode> = Object.fromEntries(nodes.map(n => [n.id, n]));
  const steps = order.map(sid => {
    const n = map[sid];
    const h: any = { id: n.data.id, name: n.data.name, call: n.data.call };
    const it = n.data.input_template; if (it && Object.keys(it).length) h.input_template = it;
    // Convert deps from node.id (string) to data.id (number)
    const deps = (depsMap[sid] || []).filter(Boolean).map(depNodeId => map[depNodeId]?.data.id).filter(Boolean);
    if (deps.length) h.deps = deps;
    return h;
  });
  const clean = cleanRules(rules);
  const payload: any = { id, name: name || id, description: description || '', driver_version: driverVersion || 'stable', version: version || 1, steps };
  payload.rules = clean;
  return YAML.dump(payload);
}

export default function ThinkWorkflowEditor() {
  const { id: routeId } = useParams();
  // Treat absence of :id param as Create mode
  const isNew = !routeId;
  const nav = useNavigate();
  const theme = useTheme();
  const [wfId, setWfId] = React.useState(routeId || '');
  const rd = useThinkWorkflowRead(isNew ? '_template' : wfId);
  const prompts = useThinkPrompts();
  const rulesList = useRules();
  const init = React.useMemo(() => defaultGraph(), []);
  const [nodes, setNodes, onNodesChange] = useNodesState<RFNode>(init.nodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>(init.edges);
  const [yamlPreview, setYamlPreview] = React.useState<string>('');
  const [previewOpen, setPreviewOpen] = React.useState(false);
  const [rightTab, setRightTab] = React.useState(0); // 0: Graph, 1: YAML
  const [validation, setValidation] = React.useState<string>('');
  const [selId, setSelId] = React.useState<string | null>(null);
  const [selEdgeId, setSelEdgeId] = React.useState<string | null>(null);
  const [selKind, setSelKind] = React.useState<'node' | 'edge' | null>(null);
  // Draft state to avoid flicker while typing JSON
  const [itDraft, setItDraft] = React.useState<string>('');
  const [itErr, setItErr] = React.useState<string | null>(null);
  const [diagramOpen, setDiagramOpen] = React.useState(false);
  const [diagramSvg, setDiagramSvg] = React.useState<string>('');
  const [diagramBusy, setDiagramBusy] = React.useState(false);
  const [diagramErr, setDiagramErr] = React.useState<string | null>(null);
  const selectedNode = React.useMemo(() => nodes.find(n => n.id === selId) || null, [nodes, selId]);
  const [callDraft, setCallDraft] = React.useState('');
  const [nameDraft, setNameDraft] = React.useState('');
  const [description, setDescription] = React.useState('');
  const [nextId, setNextId] = React.useState(1);
  const [driverVersion, setDriverVersion] = React.useState('stable');
  const [name, setName] = React.useState('');
  const [version, setVersion] = React.useState(1);
  const [rules, setRules] = React.useState<string[]>([]);
  const [saveToast, setSaveToast] = React.useState(false);
  const selectedDeps = React.useMemo(() => {
    if (!selId) return [] as string[];
    const d = edges.filter(e => e.target === selId && e.source).map(e => String(e.source));
    return Array.from(new Set(d));
  }, [edges, selId]);
  const selectedEdge = React.useMemo(() => edges.find(e => e.id === selEdgeId) || null, [edges, selEdgeId]);
  const validationTone = React.useMemo(() => {
    if (!validation) return null;
    const msg = validation.toLowerCase();
    return (msg.includes('ok') || msg.includes('saved')) ? 'success' : 'error';
  }, [validation]);
  const availableRules = rulesList.data?.rules || [];
  const selectedRuleObjects = React.useMemo(() => {
    const map = new Map(availableRules.map((r) => [r.name, r]));
    return rules.map((name) => map.get(name) || { name });
  }, [availableRules, rules]);

  // Initialize drafts when selection changes
  React.useEffect(() => {
    if (!selectedNode) { setItDraft(''); setItErr(null); setNameDraft(''); return; }
    try {
      const txt = selectedNode.data.input_template ? JSON.stringify(selectedNode.data.input_template, null, 2) : '';
      setItDraft(txt);
      setItErr(null);
    } catch { setItDraft(''); setItErr(null); }
    setCallDraft(selectedNode?.data.call || '');
    setNameDraft(selectedNode?.data.name || '');
  }, [selectedNode?.id]);

  // --- Auto layout helpers (top-to-bottom with same-level alignment) ---
  const ORIGIN_X = 120, ORIGIN_Y = 120, GRID_X = 220, GRID_Y = 120;
  const computeLevels = React.useCallback((ids: string[], es: Edge[]) => {
    const indeg: Record<string, number> = {};
    const children: Record<string, string[]> = {};
    ids.forEach(id => { indeg[id] = 0; children[id] = []; });
    es.forEach(e => {
      const u = String(e.source || '');
      const v = String(e.target || '');
      if (u && v && indeg[v] !== undefined && indeg[u] !== undefined) {
        indeg[v] += 1;
        children[u].push(v);
      }
    });
    const level: Record<string, number> = {};
    const q: string[] = ids.filter(id => indeg[id] === 0);
    q.forEach(id => { level[id] = 0; });
    const dq: string[] = [...q];
    while (dq.length) {
      const u = dq.shift() as string;
      const lu = level[u] || 0;
      (children[u] || []).forEach(v => {
        level[v] = Math.max(level[v] || 0, lu + 1);
        indeg[v] -= 1;
        if (indeg[v] === 0) dq.push(v);
      });
    }
    return level;
  }, []);

  function layoutGraph() {
    const ids = nodes.map(n => n.id);
    const lvl = computeLevels(ids, edges);
    const groups: Record<number, string[]> = {};
    ids.forEach(id => {
      const l = lvl[id] ?? 0;
      if (!groups[l]) groups[l] = [];
      groups[l].push(id);
    });
    Object.keys(groups).forEach(k => groups[Number(k)].sort());
    const newNodes = nodes.map(n => {
      const l = lvl[n.id] ?? 0;
      const idx = groups[l].indexOf(n.id);
      const x = ORIGIN_X + idx * GRID_X;
      const y = ORIGIN_Y + l * GRID_Y;
      return { ...n, position: { x, y } } as RFNode;
    });
    setNodes(newNodes);
  }

  // Auto-select first node once after initial load
  const didAutoSelectRef = React.useRef(false);
  React.useEffect(() => {
    if (!didAutoSelectRef.current && nodes.length > 0 && !selId) {
      setSelection(nodes[0].id);
      didAutoSelectRef.current = true;
    }
  }, [nodes]);

  const applySelectionStyling = (id: string | null) => {
    setNodes(ns => ns.map(n => {
      const selected = n.id === id;
      const base = { borderRadius: 6 } as React.CSSProperties;
      const style = selected
        ? { ...base, border: '2px solid #2e7d32', boxShadow: '0 0 0 2px rgba(46,125,50,0.2)' }
        : { ...base, border: '1px solid #bbb' };
      return { ...n, style } as RFNode;
    }));
  };

  const applyEdgeSelectionStyling = (edgeId: string | null) => {
    setEdges(es => es.map(e => {
      const selected = e.id === edgeId;
      const edgeColor = theme.palette.mode === 'dark' ? '#90caf9' : '#283593';
      const defaultColor = theme.palette.mode === 'dark' ? '#666' : '#bbb';
      const style = selected ? { stroke: edgeColor, strokeWidth: 2 } : { stroke: defaultColor, strokeWidth: 1 };
      return { ...e, style } as Edge;
    }));
  };

  const setSelection = (id: string | null) => {
    setSelEdgeId(null);
    setSelId(id);
    setSelKind(id ? 'node' : null);
    applySelectionStyling(id);
    applyEdgeSelectionStyling(null);
  };

  const setEdgeSelection = (edgeId: string | null) => {
    setSelId(null);
    setSelEdgeId(edgeId);
    setSelKind(edgeId ? 'edge' : null);
    applySelectionStyling(null);
    applyEdgeSelectionStyling(edgeId);
  };

  // Update nextId whenever nodes change
  React.useEffect(() => {
    if (nodes.length === 0) {
      setNextId(1);
      return;
    }
    const maxId = Math.max(...nodes.map(n => n.data.id || 0));
    setNextId(maxId + 1);
  }, [nodes]);

  React.useEffect(() => {
    if (!rd.data?.workflow_yaml) return;
    try {
      const y = YAML.load(rd.data.workflow_yaml) as any;
      setDescription(typeof y?.description === 'string' ? y.description : '');
      setDriverVersion(typeof y?.driver_version === 'string' ? y.driver_version : 'stable');
      const fallbackName = y?.name || y?.workflow || y?.id || routeId || '';
      setName(String(fallbackName || ''));
      setVersion(Number(y?.version || 1));
      const yRules = Array.isArray(y?.rules) ? y.rules.map((r: any)=> String(r || '')) : [];
      setRules(yRules);
      const steps: any[] = Array.isArray(y?.steps) ? y.steps : [];
        const npos: RFNode[] = steps.map((s, i) => {
          // Parse ID - could be number or string from YAML
          const parsedId = typeof s.id === 'number' ? s.id : (isNaN(Number(s.id)) ? (i + 1) : Number(s.id));
          // Use name field if it exists, otherwise fall back to old ID format
          const stepName = s.name || (typeof s.id === 'string' && isNaN(Number(s.id)) ? s.id : `step_${parsedId}`);

          return {
            id: String(parsedId),
            data: {
              id: parsedId,
              name: stepName,
              call: String(s.call || ''),
              input_template: s.input_template || undefined,
              capture_as: s.capture_as || undefined,
              label: `${parsedId} ${stepName}`
            },
            position: { x: 120, y: 120 + i * 120 },
            type: 'default'
          };
        });
        // Create mapping of original step IDs to parsed integer IDs
        const stepIdMap = new Map<any, number>();
        steps.forEach((s, i) => {
          const parsedId = typeof s.id === 'number' ? s.id : (isNaN(Number(s.id)) ? (i + 1) : Number(s.id));
          stepIdMap.set(s.id, parsedId);
        });

        const depEdges: Edge[] = steps.flatMap((s, _i) => {
          const targetId = stepIdMap.get(s.id) || s.id;
          return (Array.isArray(s.deps) ? s.deps : []).map((d: any, j: number) => {
            const sourceId = stepIdMap.get(d) || d;
            return {
              id: `e${String(sourceId)}-${String(targetId)}-${j}`,
              source: String(sourceId),
              target: String(targetId)
            };
          });
        });
        // Auto-align positions based on deps for initial load
        const ids = npos.map(n => n.id);
        const lvl = computeLevels(ids, depEdges);
        const groups: Record<number, string[]> = {};
        ids.forEach(id => { const l = (lvl as any)[id] ?? 0; (groups[l] ||= []).push(id); });
        Object.keys(groups).forEach(k => groups[Number(k)].sort());
        const positioned = npos.map(n => {
          const l = (lvl as any)[n.id] ?? 0;
          const idx = groups[l].indexOf(n.id);
          return { ...n, position: { x: ORIGIN_X + idx * GRID_X, y: ORIGIN_Y + l * GRID_Y } } as RFNode;
        });
        setNodes(positioned);
        setEdges(depEdges);
        // Allow auto-select to run again for this loaded workflow
      didAutoSelectRef.current = false;
    } catch { /* ignore */ }
  }, [rd.data?.workflow_yaml, computeLevels, routeId]);

  React.useEffect(() => {
    const list = prompts.data?.versions || [];
    if (!list.length) return;
    const versions = list.map(v => v.version);
    if (driverVersion && versions.includes(driverVersion)) return;
    const stable = list.find(v => v.version === 'stable');
    if (stable) { setDriverVersion(stable.version); return; }
    if (!driverVersion && list[0]?.version) { setDriverVersion(list[0].version); return; }
    if (!versions.includes(driverVersion)) { setDriverVersion(list[0].version); }
  }, [driverVersion, prompts.data?.versions]);

  React.useEffect(() => {
    if (!isNew) return;
    const slug = slugifyName(name);
    if (slug && slug !== wfId) setWfId(slug);
  }, [name, isNew, wfId]);

  const addRuleField = () => setRules(r => [...r, '']);
  const updateRuleField = (idx: number, value: string) => setRules(r => r.map((rule, i) => i === idx ? value : rule));
  const removeRuleField = (idx: number) => setRules(r => r.filter((_, i) => i !== idx));

  const onConnect = React.useCallback((c: Connection) => setEdges((eds) => addEdge(c as any, eds)), []);

  const addNode = () => {
    const newId = nextId;
    const nodeId = String(newId);
    const newName = `step_${newId}`;
    setNodes([...nodes, {
      id: nodeId,
      data: {
        id: newId,
        name: newName,
        call: 'prompt_say',
        input_template: { text: '...' },
        label: `${newId} ${newName}`
      },
      position: { x: 120, y: 120 + (nodes.length) * 120 },
      type: 'default'
    } as RFNode]);
    setTimeout(() => setSelection(nodeId), 0);
  };

  const removeSelected = () => {
    if (!selId) return;
    const remainingNodes = nodes.filter(n => n.id !== selId);
    const remainingEdges = edges.filter(e => e.source !== selId && e.target !== selId);
    setNodes(remainingNodes);
    setEdges(remainingEdges);
    setSelId(null);
    setSelKind(null);
  };

  const removeSelectedEdge = () => {
    if (!selEdgeId) return;
    const remainingEdges = edges.filter(e => e.id !== selEdgeId);
    setEdges(remainingEdges);
    setSelEdgeId(null);
    setSelKind(null);
  };

  const computeResequencedGraph = (currentNodes: RFNode[], currentEdges: Edge[]) => {
    // Sort nodes by current ID
    const sorted = [...currentNodes].sort((a, b) => a.data.id - b.data.id);

    // Create mapping of old node.id (string) -> new data.id (number)
    const idMap = new Map<string, number>();
    sorted.forEach((node, index) => {
      idMap.set(node.id, index + 1);
    });

    // Renumber nodes
    const resequencedNodes = sorted.map((node, index) => {
      const newId = index + 1;
      return {
        ...node,
        id: String(newId),
        data: {
          ...node.data,
          id: newId,
          label: `${newId} ${node.data.name}`
        }
      } as RFNode;
    });

    // Update edges with new IDs
    const resequencedEdges = currentEdges.map(edge => ({
      ...edge,
      source: String(idMap.get(edge.source as string) || edge.source),
      target: String(idMap.get(edge.target as string) || edge.target)
    }));

    return { nodes: resequencedNodes, edges: resequencedEdges, idMap };
  };

  const save = async () => {
    const slug = slugifyName(name);
    if (!slug) { setValidation('Name is required to generate workflow id'); return; }
    if (isNew && slug !== wfId) setWfId(slug);
    const currId = isNew ? slug : wfId;

    // Auto-resequence IDs before saving
    const { nodes: resequencedNodes, edges: resequencedEdges, idMap } = computeResequencedGraph(nodes, edges);

    // Apply pending draft for input_template if selection exists
    if (selectedNode) {
      try {
        const parsed = itDraft ? JSON.parse(itDraft) : undefined;
        const targetNodeId = String(idMap.get(selectedNode.id) || selectedNode.id);
        const nodeToUpdate = resequencedNodes.find(n => n.id === targetNodeId);
        if (nodeToUpdate) {
          nodeToUpdate.data.input_template = parsed;
        }
        setItErr(null);
      } catch (e: any) {
        setItErr(e?.message || 'Invalid JSON');
        setValidation('Fix input_template JSON before saving');
        return;
      }
    }
    try {
      const nextVersion = isNew ? 1 : (version || 0) + 1;
      const graph = toGraphPayload(resequencedNodes, resequencedEdges, description, driverVersion, name || currId, rules, nextVersion);
      const v = await thinkWorkflowValidateGraph(graph);
      if (!v.ok) { setValidation(v.errors.join('\n')); return; }

      if (isNew) {
        await thinkWorkflowCreateGraph(currId, graph);
        setVersion(nextVersion);
        setValidation('Saved successfully');
        setSaveToast(true);
      } else {
        try {
          await thinkWorkflowUpdateGraph(currId, graph);
          setVersion(nextVersion);
          setValidation('Saved successfully');
          setSaveToast(true);
        } catch (e: any) {
          const msg = (e?.response?.data?.error || e?.message || '').toString();
          if (msg.includes('WORKFLOW_NOT_FOUND')) {
            // Fallback: create if missing (e.g., file deleted or new id)
            await thinkWorkflowCreateGraph(currId, graph);
            setVersion(nextVersion);
            setValidation('Created new workflow (missing original).');
            setSaveToast(true);
          } else {
            setValidation(msg || 'Save failed');
            return;
          }
        }
      }

      // Update state with resequenced nodes and edges after successful save
      setNodes(resequencedNodes);
      setEdges(resequencedEdges);
      // Update selection if it existed
      if (selId && idMap.has(selId)) {
        setSelection(String(idMap.get(selId)));
      }

      try { await rd.refetch?.(); } catch {}
    } catch (e: any) {
      const msg = (e?.response?.data?.error || e?.message || '').toString();
      setValidation(msg || 'Save failed');
    }
  };

  // Keep YAML preview up-to-date with current editor state
  React.useEffect(() => {
    const currId = isNew ? slugifyName(name) || wfId || 'workflow' : wfId || 'workflow';
    setYamlPreview(toYamlPreview(nodes, edges, currId, description, driverVersion, name || currId, rules, version));
  }, [nodes, edges, name, description, driverVersion, rules, version, wfId, isNew]);

  const preview = async () => {
    const currId = isNew ? slugifyName(name) || wfId : wfId;
    if (!currId) { setValidation('Name is required'); return; }
    const graph = toGraphPayload(nodes, edges, description, driverVersion, name || currId, rules, version);
    const v = await thinkWorkflowValidateGraph(graph);
    if (!v.ok) { setValidation(v.errors.join('\n')); return; }
    setPreviewOpen(true);
  };

  // Lazy mermaid loader (shared pattern from Workflows page)
  const MERMAID_CDN = 'https://cdn.jsdelivr.net/npm/mermaid@11.4.0/dist/mermaid.esm.min.mjs';
  let mermaidInstance: any = (window as any).__savantMermaid || null;
  async function getMermaid() {
    if (mermaidInstance) return mermaidInstance;
    let m: any;
    try {
      m = await import('mermaid');
    } catch (err) {
      m = await import(MERMAID_CDN);
    }
    mermaidInstance = (m && (m.default || m)) as any;
    mermaidInstance.initialize({ startOnLoad: false, theme: 'default', flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis' }, securityLevel: 'loose' });
    (window as any).__savantMermaid = mermaidInstance;
    return mermaidInstance;
  }

  const previewDiagram = async () => {
    try {
      setDiagramErr(null);
      setDiagramBusy(true);
      const currId = isNew ? slugifyName(name) || wfId || 'workflow' : wfId || 'workflow';
      const yaml = toYamlPreview(nodes, edges, currId, description, driverVersion, name || currId, rules, version);
      const code = workflowToMermaid(yaml);
      const mm = await getMermaid();
      const { svg } = await mm.render(`wf-${Date.now()}`, code);
      setDiagramSvg(svg);
      setDiagramOpen(true);
    } catch (e: any) {
      setDiagramErr(e?.message || String(e));
      setDiagramSvg('');
      setDiagramOpen(true);
    } finally {
      setDiagramBusy(false);
    }
  };

  const updateNodeData = (id: string, key: string, value: any) => {
    setNodes(ns => ns.map(n => {
      if (n.id !== id) return n;
      const updatedData = { ...n.data, [key]: value };
      // If name is being updated, also update the label
      if (key === 'name') {
        updatedData.label = `${n.data.id} ${value}`;
      }
      return { ...n, data: updatedData };
    }));
  };

  return (
    <>
      <GlobalStyles
        styles={{
          '.react-flow__edge-text, .react-flow__edge-textbg': {
            fill: theme.palette.mode === 'dark' ? '#f8fafc' : '#111827'
          },
          '.react-flow__node-default': {
            backgroundColor: theme.palette.background.paper,
            color: theme.palette.text.primary,
            border: `1px solid ${theme.palette.mode === 'dark' ? '#334155' : '#cbd5e1'}`
          },
          '.react-flow__handle': {
            backgroundColor: theme.palette.mode === 'dark' ? '#64748b' : '#94a3b8'
          }
        }}
      />
      <Grid container spacing={2} columns={12}>
        <Grid size={12}>
        <Stack direction="row" spacing={0.5} alignItems="center" justifyContent="flex-end">
          <Stack direction="row" spacing={0.5} alignItems="center" sx={{ mr: 'auto' }}>
            <IconButton onClick={() => nav('/engines/think/workflows')} title="Back to workflows">
              <ArrowBackIcon />
            </IconButton>
            {validation && (
              <Chip
                size="small"
                label={validation}
                color={validationTone === 'success' ? 'success' : 'error'}
              />
            )}
          </Stack>
          <Tooltip title="Validate">
            <span>
              <IconButton onClick={async ()=>{ const v = await thinkWorkflowValidateGraph(toGraphPayload(nodes, edges, description, driverVersion, name || wfId, rules, version)); setValidation(v.ok? 'OK' : v.errors.join('\n')); }}>
                <TaskAltIcon />
              </IconButton>
            </span>
          </Tooltip>
          {/* YAML preview moved to right Result panel tabs */}
          <Tooltip title="Auto Align">
            <span>
              <IconButton onClick={layoutGraph}>
                <AutoFixHighIcon />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title={diagramBusy ? 'Rendering…' : 'View Diagram'}>
            <span>
              <IconButton onClick={previewDiagram} disabled={diagramBusy} color="primary">
                <AccountTreeIcon />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title="Save workflow">
            <span>
              <IconButton onClick={save} disabled={!wfId} color="primary">
                <SaveIcon />
              </IconButton>
            </span>
          </Tooltip>
        </Stack>
      </Grid>
      {/* Two-panel layout: Action (left) and Result (right) — 4/8 split */}
      <Grid size={4}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <Box id="workflow-actions-panel" aria-labelledby="workflow-actions-heading" sx={{ flex: 1, overflowY: 'auto', pr: 1 }}>
            <Typography id="workflow-actions-heading" component="span" sx={{ position: 'absolute', width: 1, height: 1, padding: 0, margin: -1, overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap', border: 0 }}>Workflow Actions Panel</Typography>
            <Stack spacing={1.5} sx={{ mb: 2, mt: 1 }}>
              <Stack direction={{ xs: 'column', md: 'row' }} spacing={1.5} alignItems="center">
                <Stack direction="row" spacing={1} alignItems="center">
                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Workflow ID</Typography>
                  <Chip label={wfId || 'new'} size="small" color="default" />
                </Stack>
                <Stack direction="row" spacing={1} alignItems="center">
                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Version</Typography>
                  <Chip label={`v${version}`} size="small" color="primary" />
                </Stack>
              </Stack>
              <TextField id="wf-name" name="workflowName" label="Name" value={name} onChange={(e)=>setName(e.target.value)} placeholder="Workflow name" fullWidth />
              <TextField id="wf-driver" name="workflowDriver" label="Driver Version" select value={driverVersion} onChange={(e)=>setDriverVersion(e.target.value)} fullWidth>
                {(prompts.data?.versions || [{ version: 'stable', path: '' }]).map(v => (
                  <MenuItem key={v.version} value={v.version}>{v.version}</MenuItem>
                ))}
              </TextField>
              <Stack spacing={1.5}>
                <Typography variant="caption" sx={{ fontWeight: 600 }}>Rules</Typography>
                <Autocomplete
                  multiple
                  options={availableRules}
                  getOptionLabel={(option) => option.name}
                  value={selectedRuleObjects}
                  onChange={(_, newValue) => setRules(newValue.map((r) => r.name))}
                  disableCloseOnSelect
                  loading={rulesList.isLoading}
                  isOptionEqualToValue={(option, value) => option.name === value.name}
                  renderInput={(params) => (
                    <TextField
                      {...params}
                      label="Select rules"
                      placeholder={availableRules.length ? 'Type to find rules' : 'No rules available'}
                    />
                  )}
                  renderTags={(tagValue, getTagProps) =>
                    tagValue.map((option, index) => {
                      const { key, ...chipProps } = getTagProps({ index });
                      return (
                        <Chip
                          key={key}
                          {...chipProps}
                          label={option.name}
                          size="small"
                        />
                      );
                    })
                  }
                />
              </Stack>
              <TextField
                id="wf-desc"
                name="workflowDescription"
                label="Description"
                value={description}
                onChange={(e)=>setDescription(e.target.value)}
                placeholder="Enter workflow description"
                fullWidth
                multiline
                minRows={3}
              />
            </Stack>
            <Stack direction="row" spacing={1} sx={{ mb: 1 }}>
              <Button startIcon={<AddBoxIcon />} onClick={addNode}>Add Step</Button>
              <Button startIcon={<DeleteOutlineIcon />} onClick={removeSelected} disabled={!selId}>Remove Step</Button>
              <Button startIcon={<DeleteOutlineIcon />} onClick={removeSelectedEdge} disabled={!selEdgeId}>Remove Edge</Button>
            </Stack>
            <Divider sx={{ my: 1 }} />
            <Typography variant="subtitle2" sx={{ mb: 1 }}>Properties</Typography>
            {selEdgeId && selectedEdge ? (
              <Box sx={{ border: '2px solid', borderColor: 'success.main', borderRadius: 1, p: 1, mb: 1 }}>
                <Typography variant="caption" sx={{ fontWeight: 600 }}>Edge</Typography>
                <TextField id={`edge-id-${selectedEdge.id}`} name="edgeId" label="id" fullWidth sx={{ mt: 1 }} value={selectedEdge.id} InputProps={{ readOnly: true }} />
                <TextField id={`edge-src-${selectedEdge.id}`} name="source" label="source" fullWidth sx={{ mt: 1 }} value={String(selectedEdge.source || '')} InputProps={{ readOnly: true }} />
                <TextField id={`edge-tgt-${selectedEdge.id}`} name="target" label="target" fullWidth sx={{ mt: 1 }} value={String(selectedEdge.target || '')} InputProps={{ readOnly: true }} />
              </Box>
            ) : !selectedNode ? (
              <Alert severity="info">Select a step or edge to view properties</Alert>
            ) : (
              <Box
                key={selectedNode.id}
                sx={{
                  border: '2px solid',
                  borderColor: 'success.main',
                  borderRadius: 1,
                  p: 1,
                  mb: 1
                }}
              >
                <Stack direction="row" spacing={1} alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
                  <Typography variant="caption" sx={{ fontWeight: 600 }}>Step ID</Typography>
                  <Chip label={selectedNode.data.id} size="small" color="primary" />
                </Stack>
                <TextField
                  id="step-name-field"
                  name="stepName"
                  label="name"
                  value={nameDraft}
                  size="small"
                  fullWidth
                  onChange={(e)=> setNameDraft(e.target.value)}
                  onBlur={()=> updateNodeData(selectedNode.id, 'name', nameDraft)}
                  sx={{ mb: 1 }}
                />
                <TextField id={`step-call-${selectedNode.id}`} name="call" label="call" fullWidth sx={{ mt: 1 }} value={callDraft} onChange={(e)=>setCallDraft(e.target.value)} onBlur={()=>updateNodeData(selectedNode.id, 'call', callDraft)} />
                <TextField id={`step-deps-${selectedNode.id}`} name="deps" label="deps" fullWidth sx={{ mt: 1 }} value={selectedDeps.join(', ')} InputProps={{ readOnly: true }} />
                <TextField id={`step-input-template-${selectedNode.id}`} name="input_template" label="input_template (JSON)" fullWidth multiline minRows={3} sx={{ mt: 1 }}
                          value={itDraft}
                          error={!!itErr}
                          helperText={itErr || ''}
                          onChange={(e)=>{ setItDraft(e.target.value); setItErr(null); }}
                          onBlur={() => { try { const parsed = itDraft ? JSON.parse(itDraft) : undefined; updateNodeData(selectedNode.id, 'input_template', parsed); setItErr(null);} catch (e:any) { setItErr(e?.message || 'Invalid JSON'); } }}
                />
              </Box>
            )}
          </Box>
        </Paper>
      </Grid>
      <Grid size={8}>
        <Paper sx={{ p: 1, height: PANEL_HEIGHT, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          {rd.isFetching && <LinearProgress />}
          {rd.isError && <Alert severity="error">{(rd.error as any)?.message || 'Failed to load'}</Alert>}
          <Stack direction="row" alignItems="center" justifyContent="flex-end" sx={{ px: 1 }}>
            <Tooltip title="Copy YAML">
              <IconButton onClick={() => { try { navigator.clipboard.writeText(yamlPreview); } catch { /* ignore */ } }}>
                <ContentCopyIcon fontSize="small" />
              </IconButton>
            </Tooltip>
            <Tooltip title="Preview YAML">
              <IconButton onClick={preview} color="primary">
                <VisibilityIcon fontSize="small" />
              </IconButton>
            </Tooltip>
          </Stack>
          <Box sx={{ flex: 1, minHeight: 0, width: '100%', overflow: 'auto' }}>
            <ReactFlow
              style={{
                width: '100%',
                height: '100%',
                backgroundColor: theme.palette.background.paper
              }}
              nodes={nodes}
              edges={edges}
              onNodesChange={onNodesChange}
              onEdgesChange={onEdgesChange}
              onConnect={onConnect}
              onSelectionChange={(s: any) => {
                if (s?.edges && s.edges.length > 0) {
                  const eid = s.edges[0].id;
                  if (eid !== selEdgeId) setEdgeSelection(eid);
                } else if (s?.nodes && s.nodes.length > 0) {
                  const id = s.nodes[0].id;
                  if (id !== selId) setSelection(id);
                }
              }}
            >
              <MiniMap
                nodeColor={theme.palette.mode === 'dark' ? '#90caf9' : '#283593'}
                maskColor={theme.palette.mode === 'dark' ? 'rgba(17,24,39,0.8)' : 'rgba(255,255,255,0.8)'}
              />
              <Controls />
              <Background
                color={theme.palette.mode === 'dark' ? '#334155' : '#aaa'}
                gap={16}
              />
            </ReactFlow>
          </Box>
        </Paper>
      </Grid>
      <Dialog open={previewOpen} onClose={() => setPreviewOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          YAML Preview — {wfId || slugifyName(name) || 'workflow'}
          <IconButton size="small" onClick={() => setPreviewOpen(false)}>
            <CloseIcon fontSize="small" />
          </IconButton>
        </DialogTitle>
        <DialogContent dividers>
          <Viewer content={yamlPreview || ''} language="yaml" height={420} />
        </DialogContent>
        <DialogActions>
          <Tooltip title="Close">
            <IconButton onClick={() => setPreviewOpen(false)}>
              <CloseIcon />
            </IconButton>
          </Tooltip>
        </DialogActions>
      </Dialog>
      {/* YAML preview is now inline in the right panel */}
      <WorkflowDiagram
        open={diagramOpen}
        onClose={() => setDiagramOpen(false)}
        svgContent={diagramSvg}
        workflowName={wfId || undefined}
      />
      <Snackbar
        open={saveToast}
        autoHideDuration={2000}
        onClose={() => setSaveToast(false)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert onClose={() => setSaveToast(false)} severity="success" sx={{ width: '100%' }}>
          Workflow saved
        </Alert>
      </Snackbar>
    </Grid>
    </>
  );
}
