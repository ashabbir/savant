import React from 'react';
import ReactFlow, { Background, Controls, MiniMap, addEdge, Connection, Edge, Node, useNodesState, useEdgesState } from 'reactflow';
import 'reactflow/dist/style.css';
import { Alert, Box, Button, Divider, Grid2 as Grid, IconButton, LinearProgress, Paper, Stack, TextField, Tooltip, Typography, Dialog, DialogTitle, DialogContent, DialogActions } from '@mui/material';
import SaveIcon from '@mui/icons-material/Save';
import VisibilityIcon from '@mui/icons-material/Visibility';
import TaskAltIcon from '@mui/icons-material/TaskAlt';
import AddBoxIcon from '@mui/icons-material/AddBox';
import AccountTreeIcon from '@mui/icons-material/AccountTree';
import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import { useNavigate, useParams } from 'react-router-dom';
import { useThinkWorkflowRead } from '../../api';
import { thinkWorkflowCreateGraph, thinkWorkflowUpdateGraph, thinkWorkflowValidateGraph } from '../../thinkApi';
import YAML from 'js-yaml';
import Viewer from '../../components/Viewer';
import WorkflowDiagram from '../../components/WorkflowDiagram';
import { workflowToMermaid } from '../../utils/workflowToMermaid';

type RFNode = Node<{ call: string; input_template?: any; capture_as?: string; label?: string }>;

function defaultGraph(): { nodes: RFNode[]; edges: Edge[] } {
  const nodes: RFNode[] = [
    { id: 'step_1', position: { x: 120, y: 120 }, data: { call: 'prompt.say', input_template: { text: 'Start' }, label: 'step_1' }, type: 'default' },
    { id: 'step_2', position: { x: 120, y: 240 }, data: { call: 'prompt.say', input_template: { text: 'Done' }, label: 'step_2' }, type: 'default' }
  ];
  const edges: Edge[] = [{ id: 'e1-2', source: 'step_1', target: 'step_2' }];
  return { nodes, edges };
}

function toGraphPayload(nodes: RFNode[], edges: Edge[]) {
  return {
    nodes: nodes.map(n => ({ id: n.id, call: n.data.call, input_template: n.data.input_template, capture_as: n.data.capture_as })),
    edges: edges.map(e => ({ source: e.source, target: e.target }))
  };
}

function toYamlPreview(nodes: RFNode[], edges: Edge[], id: string) {
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
    const h: any = { id: sid, call: n.data.call };
    const it = n.data.input_template; if (it && Object.keys(it).length) h.input_template = it;
    const deps = (depsMap[sid] || []).filter(Boolean);
    if (deps.length) h.deps = deps;
    return h;
  });
  return YAML.dump({ id, title: id, description: '', steps });
}

export default function ThinkWorkflowEditor() {
  const { id: routeId } = useParams();
  // Treat absence of :id param as Create mode
  const isNew = !routeId;
  const nav = useNavigate();
  const [wfId, setWfId] = React.useState(routeId || '');
  const rd = useThinkWorkflowRead(isNew ? null : wfId);
  const init = React.useMemo(() => defaultGraph(), []);
  const [nodes, setNodes, onNodesChange] = useNodesState<RFNode>(init.nodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>(init.edges);
  const [yamlPreview, setYamlPreview] = React.useState<string>('');
  const [validation, setValidation] = React.useState<string>('');
  const [previewOpen, setPreviewOpen] = React.useState(false);
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
  const selectedDeps = React.useMemo(() => {
    if (!selId) return [] as string[];
    const d = edges.filter(e => e.target === selId && e.source).map(e => String(e.source));
    return Array.from(new Set(d));
  }, [edges, selId]);

  // Initialize drafts when selection changes
  React.useEffect(() => {
    if (!selectedNode) { setItDraft(''); setItErr(null); return; }
    try {
      const txt = selectedNode.data.input_template ? JSON.stringify(selectedNode.data.input_template, null, 2) : '';
      setItDraft(txt);
      setItErr(null);
    } catch { setItDraft(''); setItErr(null); }
    setCallDraft(selectedNode?.data.call || '');
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

  // Auto-select first node when nodes are ready and nothing selected yet
  React.useEffect(() => {
    if (!selId && nodes.length > 0) {
      setSelection(nodes[0].id);
    }
  }, [nodes, selId]);

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
      const style = selected ? { stroke: '#2e7d32', strokeWidth: 2 } : { stroke: '#bbb', strokeWidth: 1 };
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

  // Helper to normalize/validate node IDs
  const normalizeId = (s: string) => (s || '').trim().replace(/[^A-Za-z0-9_.-]/g, '_');

  const renameNode = (oldId: string, newIdRaw: string) => {
    const newId = normalizeId(newIdRaw);
    if (!newId || newId === oldId) return;
    // Prevent duplicates
    if (nodes.some(n => n.id === newId)) {
      setValidation(`Duplicate id: ${newId}`);
      return;
    }
    // Rename in nodes
    const renamedNodes = nodes.map(n => n.id === oldId ? { ...n, id: newId, data: { ...n.data, label: newId } } as RFNode : n);
    // Update edges
    const renamedEdges = edges.map(e => ({
      ...e,
      source: e.source === oldId ? newId : e.source,
      target: e.target === oldId ? newId : e.target
    }));
    setNodes(renamedNodes);
    setEdges(renamedEdges);
    if (selId === oldId) setSelection(newId);
  };

  React.useEffect(() => {
    if (!isNew && rd.data?.workflow_yaml) {
      try {
        const y = YAML.load(rd.data.workflow_yaml) as any;
        const steps: any[] = Array.isArray(y?.steps) ? y.steps : [];
        const npos: RFNode[] = steps.map((s, i) => ({ id: String(s.id), data: { call: String(s.call || ''), input_template: s.input_template || undefined, capture_as: s.capture_as || undefined, label: String(s.id) }, position: { x: 120, y: 120 + i * 120 }, type: 'default' }));
        const depEdges: Edge[] = steps.flatMap((s, _i) => (Array.isArray(s.deps) ? s.deps : []).map((d: any, j: number) => ({ id: `e${String(d)}-${String(s.id)}-${j}` , source: String(d), target: String(s.id) })));
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
      } catch { /* ignore */ }
    }
  }, [rd.data?.workflow_yaml, isNew, computeLevels]);

  const onConnect = React.useCallback((c: Connection) => setEdges((eds) => addEdge(c as any, eds)), []);

  const addNode = () => {
    const num = nodes.length + 1;
    const id = `step_${num}`;
    setNodes([...nodes, { id, data: { call: 'prompt.say', input_template: { text: '...' }, label: id }, position: { x: 120, y: 120 + (nodes.length) * 120 }, type: 'default' } as RFNode]);
    setTimeout(() => setSelection(id), 0);
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

  const save = async () => {
    if (!wfId) return;
    // Apply pending draft for input_template if selection exists
    if (selectedNode) {
      try {
        const parsed = itDraft ? JSON.parse(itDraft) : undefined;
        updateNodeData(selectedNode.id, 'input_template', parsed);
        setItErr(null);
      } catch (e: any) {
        setItErr(e?.message || 'Invalid JSON');
        setValidation('Fix input_template JSON before saving');
        return;
      }
    }
    const graph = toGraphPayload(nodes, edges);
    const v = await thinkWorkflowValidateGraph(graph);
    if (!v.ok) { setValidation(v.errors.join('\n')); return; }
    if (isNew) await thinkWorkflowCreateGraph(wfId, graph);
    else await thinkWorkflowUpdateGraph(wfId, graph);
    setValidation('Saved successfully');
    nav('/engines/think/workflows');
  };

  const preview = async () => {
    if (!wfId) return;
    const graph = toGraphPayload(nodes, edges);
    const v = await thinkWorkflowValidateGraph(graph);
    if (!v.ok) { setValidation(v.errors.join('\n')); return; }
    setYamlPreview(toYamlPreview(nodes, edges, wfId));
    setPreviewOpen(true);
  };

  // Lazy mermaid loader (shared pattern from Workflows page)
  let mermaidInstance: any = (window as any).__savantMermaid || null;
  async function getMermaid() {
    if (mermaidInstance) return mermaidInstance;
    const m = await import('mermaid');
    mermaidInstance = m.default;
    mermaidInstance.initialize({ startOnLoad: false, theme: 'default', flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis' }, securityLevel: 'loose' });
    (window as any).__savantMermaid = mermaidInstance;
    return mermaidInstance;
  }

  const previewDiagram = async () => {
    try {
      setDiagramErr(null);
      setDiagramBusy(true);
      const yaml = toYamlPreview(nodes, edges, wfId || 'workflow');
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
    setNodes(ns => ns.map(n => n.id === id ? { ...n, data: { ...n.data, [key]: value } } : n));
  };

  return (
    <Grid container spacing={2} columns={12}>
      <Grid size={12}>
        <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
          <Stack direction="row" spacing={1} alignItems="center">
            <Typography variant="subtitle1">Think Workflow Builder</Typography>
            <TextField id="wf-id" name="workflowId" label="ID" value={wfId} onChange={(e)=>setWfId(e.target.value)} placeholder="new_workflow" sx={{ minWidth: 260 }} disabled={!isNew} />
          </Stack>
          <Stack direction="row" spacing={1}>
            <Tooltip title="Validate">
              <span>
                <IconButton onClick={async ()=>{ const v = await thinkWorkflowValidateGraph(toGraphPayload(nodes, edges)); setValidation(v.ok? 'OK' : v.errors.join('\n')); }}>
                  <TaskAltIcon />
                </IconButton>
              </span>
            </Tooltip>
            <Tooltip title="Preview YAML">
              <span>
                <IconButton onClick={preview}><VisibilityIcon /></IconButton>
              </span>
            </Tooltip>
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
            <Button variant="contained" startIcon={<SaveIcon />} onClick={save} disabled={!wfId}>Save</Button>
          </Stack>
        </Stack>
      </Grid>
      {/* Two-panel layout: Action (left, small) and Result (right, large) */}
      <Grid size={4}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Actions</Typography>
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
              <Stack direction="row" spacing={1} alignItems="center" justifyContent="space-between">
                <Typography variant="caption" sx={{ fontWeight: 600 }}>Step</Typography>
                <TextField
                  id={`step-id-${selectedNode.id}`}
                  name="stepId"
                  label="id"
                  value={selectedNode.id}
                  size="small"
                  onChange={(e)=> renameNode(selectedNode.id, e.target.value)}
                  sx={{ width: 180 }}
                />
              </Stack>
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
          {validation && <Alert sx={{ mt: 1 }} severity={validation.includes('OK')||validation.includes('Saved')? 'success':'warning'}>{validation}</Alert>}
        </Paper>
      </Grid>
      <Grid size={8}>
        <Paper sx={{ height: 620 }}>
          {!isNew && rd.isFetching && <LinearProgress />}
          {rd.isError && <Alert severity="error">{(rd.error as any)?.message || 'Failed to load'}</Alert>}
          <Box sx={{ height: '100%', width: '100%' }}>
            <ReactFlow
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
              <MiniMap />
              <Controls />
              <Background />
            </ReactFlow>
          </Box>
        </Paper>
      </Grid>
      <Dialog open={previewOpen} onClose={() => setPreviewOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle>YAML Preview — {wfId}</DialogTitle>
        <DialogContent dividers>
          <Viewer content={yamlPreview || ''} language="yaml" height={420} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPreviewOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>
      <WorkflowDiagram
        open={diagramOpen}
        onClose={() => setDiagramOpen(false)}
        svgContent={diagramSvg}
        workflowName={wfId || undefined}
      />
    </Grid>
  );
}
