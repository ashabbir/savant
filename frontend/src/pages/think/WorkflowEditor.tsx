import React from 'react';
import ReactFlow, { Background, Controls, MiniMap, addEdge, Connection, Edge, Node, useNodesState, useEdgesState } from 'reactflow';
import 'reactflow/dist/style.css';
import { Alert, Box, Button, Divider, Grid2 as Grid, IconButton, LinearProgress, Paper, Stack, TextField, Tooltip, Typography } from '@mui/material';
import SaveIcon from '@mui/icons-material/Save';
import VisibilityIcon from '@mui/icons-material/Visibility';
import TaskAltIcon from '@mui/icons-material/TaskAlt';
import AddBoxIcon from '@mui/icons-material/AddBox';
import { useNavigate, useParams } from 'react-router-dom';
import { useThinkWorkflowRead } from '../../api';
import { thinkWorkflowCreateGraph, thinkWorkflowUpdateGraph, thinkWorkflowValidateGraph } from '../../thinkApi';
import YAML from 'js-yaml';

type RFNode = Node<{ call: string; input_template?: any; capture_as?: string }>;

function defaultGraph(): { nodes: RFNode[]; edges: Edge[] } {
  const nodes: RFNode[] = [
    { id: 'step_1', position: { x: 120, y: 120 }, data: { call: 'prompt.say', input_template: { text: 'Start' } }, type: 'default' },
    { id: 'step_2', position: { x: 380, y: 120 }, data: { call: 'prompt.say', input_template: { text: 'Done' } }, type: 'default' }
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
  edges.forEach(e => { if (e.source && e.target) { indeg[e.target] = (indeg[e.target] || 0) + 1; (adj[e.source] ||= []).push(e.target); } });
  const q = ids.filter(i => (indeg[i] || 0) === 0);
  const order: string[] = [];
  while (q.length) { const u = q.shift()!; order.push(u); (adj[u] || []).forEach(v => { indeg[v]--; if (indeg[v] === 0) q.push(v); }); }
  const map: Record<string, RFNode> = Object.fromEntries(nodes.map(n => [n.id, n]));
  const steps = order.map(sid => {
    const n = map[sid];
    const h: any = { id: sid, call: n.data.call };
    const it = n.data.input_template; if (it && Object.keys(it).length) h.input_template = it;
    return h;
  });
  return YAML.dump({ id, title: id, description: '', steps });
}

export default function ThinkWorkflowEditor() {
  const { id: routeId } = useParams();
  const isNew = routeId === 'new';
  const nav = useNavigate();
  const [wfId, setWfId] = React.useState(isNew ? '' : (routeId || ''));
  const rd = useThinkWorkflowRead(isNew ? null : wfId);
  const init = React.useMemo(() => defaultGraph(), []);
  const [nodes, setNodes, onNodesChange] = useNodesState<RFNode>(init.nodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>(init.edges);
  const [yamlPreview, setYamlPreview] = React.useState<string>('');
  const [validation, setValidation] = React.useState<string>('');

  React.useEffect(() => {
    if (!isNew && rd.data?.workflow_yaml) {
      try {
        const y = YAML.load(rd.data.workflow_yaml) as any;
        const steps: any[] = Array.isArray(y?.steps) ? y.steps : [];
        const npos: RFNode[] = steps.map((s, i) => ({ id: String(s.id), data: { call: String(s.call || ''), input_template: s.input_template || undefined, capture_as: s.capture_as || undefined }, position: { x: 120 + i * 200, y: 120 }, type: 'default' }));
        const depEdges: Edge[] = steps.flatMap((s, _i) => (Array.isArray(s.deps) ? s.deps : []).map((d: any, j: number) => ({ id: `e${String(d)}-${String(s.id)}-${j}` , source: String(d), target: String(s.id) })));
        setNodes(npos);
        setEdges(depEdges);
      } catch { /* ignore */ }
    }
  }, [rd.data?.workflow_yaml, isNew]);

  const onConnect = React.useCallback((c: Connection) => setEdges((eds) => addEdge(c as any, eds)), []);

  const addNode = () => {
    const num = nodes.length + 1;
    const id = `step_${num}`;
    setNodes([...nodes, { id, data: { call: 'prompt.say', input_template: { text: '...' } }, position: { x: 120 + num * 40, y: 120 + num * 10 }, type: 'default' }]);
  };

  const save = async () => {
    if (!wfId) return;
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
            <TextField label="ID" value={wfId} onChange={(e)=>setWfId(e.target.value)} placeholder="new_workflow" sx={{ minWidth: 260 }} />
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
            <Button variant="contained" startIcon={<SaveIcon />} onClick={save} disabled={!wfId}>Save</Button>
          </Stack>
        </Stack>
      </Grid>
      <Grid size={2}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Palette</Typography>
          <Button fullWidth startIcon={<AddBoxIcon />} onClick={addNode}>Add Step</Button>
          <Divider sx={{ my: 1 }} />
          {validation && <Alert severity={validation.includes('OK')||validation.includes('Saved')? 'success':'warning'}>{validation}</Alert>}
        </Paper>
      </Grid>
      <Grid size={7}>
        <Paper sx={{ height: 560 }}>
          {!isNew && rd.isFetching && <LinearProgress />}
          {rd.isError && <Alert severity="error">{(rd.error as any)?.message || 'Failed to load'}</Alert>}
          <Box sx={{ height: '100%', width: '100%' }}>
            <ReactFlow nodes={nodes} edges={edges} onNodesChange={onNodesChange} onEdgesChange={onEdgesChange} onConnect={onConnect} fitView>
              <MiniMap />
              <Controls />
              <Background />
            </ReactFlow>
          </Box>
        </Paper>
      </Grid>
      <Grid size={3}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Properties</Typography>
          {nodes.map(n => (
            <Box key={n.id} sx={{ border: '1px solid #eee', borderRadius: 1, p: 1, mb: 1 }}>
              <Typography variant="caption" sx={{ fontWeight: 600 }}>{n.id}</Typography>
              <TextField label="call" fullWidth sx={{ mt: 1 }} value={n.data.call || ''} onChange={(e)=>updateNodeData(n.id, 'call', e.target.value)} />
              <TextField label="input_template (JSON)" fullWidth multiline minRows={3} sx={{ mt: 1 }} value={n.data.input_template ? JSON.stringify(n.data.input_template, null, 2) : ''}
                        onChange={(e)=>{
                          try { updateNodeData(n.id, 'input_template', e.target.value ? JSON.parse(e.target.value) : undefined); } catch { /* ignore */ }
                        }} />
            </Box>
          ))}
        </Paper>
        <Paper sx={{ p: 1, mt: 2 }}>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>YAML Preview</Typography>
          <Box component="pre" sx={{ fontSize: 12, whiteSpace: 'pre-wrap', p: 1, bgcolor: '#fafafa', maxHeight: 240, overflow: 'auto' }}>
            {yamlPreview || 'Click Preview to render YAML'}
          </Box>
        </Paper>
      </Grid>
    </Grid>
  );
}
