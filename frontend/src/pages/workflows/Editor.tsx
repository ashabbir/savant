import React from 'react';
import ReactFlow, { Background, Controls, MiniMap, addEdge, Connection, Edge, Node, NodeTypes } from 'reactflow';
import 'reactflow/dist/style.css';
import { Alert, Box, Button, Divider, Grid2 as Grid, IconButton, LinearProgress, Paper, Stack, TextField, Tooltip, Typography } from '@mui/material';
import SaveIcon from '@mui/icons-material/Save';
import VisibilityIcon from '@mui/icons-material/Visibility';
import TaskAltIcon from '@mui/icons-material/TaskAlt';
import AddBoxIcon from '@mui/icons-material/AddBox';
import { useNavigate, useParams } from 'react-router-dom';
import { useWorkflow, workflowCreate, workflowUpdate, workflowValidate } from '../../api';
import YAML from 'js-yaml';

type RFNode = Node<{ type: string; engine?: string; method?: string; args?: any; prompt?: string; value?: any } >;

function defaultGraph(): { nodes: RFNode[]; edges: Edge[] } {
  const nodes: RFNode[] = [
    { id: 'step_1', position: { x: 100, y: 100 }, data: { type: 'tool', engine: 'users', method: 'find', args: { id: '{{ input.userId }}' } }, type: 'default' },
    { id: 'step_2', position: { x: 350, y: 100 }, data: { type: 'return', value: '{{ step_1.data }}' }, type: 'default' }
  ];
  const edges: Edge[] = [{ id: 'e1-2', source: 'step_1', target: 'step_2' }];
  return { nodes, edges };
}

function toGraphPayload(nodes: RFNode[], edges: Edge[]) {
  return {
    nodes: nodes.map(n => ({ id: n.id, type: n.data.type, data: n.data })),
    edges: edges.map(e => ({ source: e.source, target: e.target }))
  };
}

function toYamlPreview(nodes: RFNode[], edges: Edge[], id: string) {
  // Client preview mirrors server mapping
  // Order nodes by simple indegree-based topo
  const ids = nodes.map(n => n.id);
  const indeg: Record<string, number> = {};
  ids.forEach(i => indeg[i] = 0);
  edges.forEach(e => { if (e.source && e.target) indeg[e.target] = (indeg[e.target] || 0) + 1; });
  const adj: Record<string, string[]> = {};
  edges.forEach(e => { if (e.source && e.target) { (adj[e.source] ||= []).push(e.target); } });
  const q = ids.filter(i => (indeg[i] || 0) === 0);
  const order: string[] = [];
  while (q.length) {
    const u = q.shift()!;
    order.push(u);
    (adj[u] || []).forEach(v => { indeg[v]--; if (indeg[v] === 0) q.push(v); });
  }
  const map: Record<string, RFNode> = Object.fromEntries(nodes.map(n => [n.id, n]));
  const steps = order.map(sid => {
    const n = map[sid];
    const t = n.data.type;
    if (t === 'tool') return { id: sid, type: 'tool', engine: n.data.engine || '', method: n.data.method || '', args: n.data.args || {} };
    if (t === 'llm') return { id: sid, type: 'llm', prompt: n.data.prompt || '' };
    if (t === 'return') return { id: sid, type: 'return', value: n.data.value };
    return { id: sid, type: t } as any;
  });
  return YAML.dump({ id, title: id, description: '', steps });
}

export default function WorkflowEditor() {
  const { id: routeId } = useParams();
  const isNew = routeId === 'new';
  const nav = useNavigate();
  const [wfId, setWfId] = React.useState(isNew ? '' : (routeId || ''));
  const rd = useWorkflow(isNew ? null : wfId);
  const init = React.useMemo(() => defaultGraph(), []);
  const [nodes, setNodes] = React.useState<RFNode[]>(init.nodes);
  const [edges, setEdges] = React.useState<Edge[]>(init.edges);
  const [yamlPreview, setYamlPreview] = React.useState<string>('');
  const [validation, setValidation] = React.useState<string>('');

  React.useEffect(() => {
    if (!isNew && rd.data?.graph) {
      const g = rd.data.graph;
      const npos = (g.nodes || []).map((n: any, i: number) => ({ id: n.id, data: { type: n.type, ...n.data }, position: { x: 100 + i * 200, y: 100 }, type: 'default' }));
      const e = (g.edges || []).map((e: any, i: number) => ({ id: `e${i}`, source: e.source, target: e.target }))
      setNodes(npos);
      setEdges(e);
    }
  }, [rd.data?.graph, isNew]);

  const onConnect = React.useCallback((c: Connection) => setEdges((eds) => addEdge(c as any, eds)), []);

  const addNode = (type: 'tool'|'llm'|'return') => {
    const num = nodes.length + 1;
    const id = `step_${num}`;
    const data: any = { type };
    if (type === 'tool') { data.engine = 'engine'; data.method = 'method'; data.args = {}; }
    if (type === 'llm') { data.prompt = 'Prompt...'; }
    if (type === 'return') { data.value = 'result'; }
    setNodes([...nodes, { id, data, position: { x: 100 + num * 40, y: 100 + num * 10 }, type: 'default' }]);
  };

  const save = async () => {
    if (!wfId) return;
    const graph = toGraphPayload(nodes, edges);
    const v = await workflowValidate(graph);
    if (!v.ok) {
      setValidation(v.errors.join('\n'));
      return;
    }
    if (isNew) await workflowCreate(wfId, graph);
    else await workflowUpdate(wfId, graph);
    setValidation('Saved successfully');
    nav('/engines/workflows');
  };

  const preview = async () => {
    if (!wfId) return;
    const graph = toGraphPayload(nodes, edges);
    const v = await workflowValidate(graph);
    if (!v.ok) { setValidation(v.errors.join('\n')); return; }
    setYamlPreview(toYamlPreview(nodes, edges, wfId));
  };

  const updateNodeData = (id: string, key: string, value: any) => {
    setNodes(ns => ns.map(n => n.id === id ? { ...n, data: { ...n.data, [key]: value } } : n));
  };

  return (
    <Grid container spacing={2} columns={12}>
      <Grid xs={12}>
        <Stack direction="row" spacing={2} alignItems="center" justifyContent="space-between">
          <Stack direction="row" spacing={1} alignItems="center">
            <Typography variant="subtitle1">Workflow Builder</Typography>
            <TextField label="ID" value={wfId} onChange={(e)=>setWfId(e.target.value)} placeholder="new_workflow" sx={{ minWidth: 260 }} />
          </Stack>
          <Stack direction="row" spacing={1}>
            <Tooltip title="Validate">
              <span>
                <IconButton onClick={async ()=>{ const v = await workflowValidate(toGraphPayload(nodes, edges)); setValidation(v.ok? 'OK' : v.errors.join('\n')); }}>
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
      <Grid xs={2}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Palette</Typography>
          <Button fullWidth startIcon={<AddBoxIcon />} onClick={() => addNode('tool')}>Tool Step</Button>
          <Button fullWidth startIcon={<AddBoxIcon />} onClick={() => addNode('llm')}>LLM Step</Button>
          <Button fullWidth startIcon={<AddBoxIcon />} onClick={() => addNode('return')}>Return Step</Button>
          <Divider sx={{ my: 1 }} />
          {validation && <Alert severity={validation.includes('OK')||validation.includes('Saved')? 'success':'warning'}>{validation}</Alert>}
        </Paper>
      </Grid>
      <Grid xs={7}>
        <Paper sx={{ height: 560 }}>
          {!isNew && rd.isFetching && <LinearProgress />}
          {rd.isError && <Alert severity="error">{(rd.error as any)?.message || 'Failed to load'}</Alert>}
          <Box sx={{ height: '100%' }}>
            <ReactFlow nodes={nodes} edges={edges} onNodesChange={setNodes as any} onEdgesChange={setEdges as any} onConnect={onConnect} fitView>
              <MiniMap />
              <Controls />
              <Background />
            </ReactFlow>
          </Box>
        </Paper>
      </Grid>
      <Grid xs={3}>
        <Paper sx={{ p: 1 }}>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>Properties</Typography>
          {nodes.map(n => (
            <Box key={n.id} sx={{ border: '1px solid #eee', borderRadius: 1, p: 1, mb: 1 }}>
              <Typography variant="caption" sx={{ fontWeight: 600 }}>{n.id} — {n.data.type}</Typography>
              {n.data.type === 'tool' && (
                <>
                  <TextField label="Engine" fullWidth sx={{ mt: 1 }} value={n.data.engine || ''} onChange={(e)=>updateNodeData(n.id, 'engine', e.target.value)} />
                  <TextField label="Method" fullWidth sx={{ mt: 1 }} value={n.data.method || ''} onChange={(e)=>updateNodeData(n.id, 'method', e.target.value)} />
                </>
              )}
              {n.data.type === 'llm' && (
                <TextField label="Prompt" fullWidth multiline minRows={3} sx={{ mt: 1 }} value={n.data.prompt || ''} onChange={(e)=>updateNodeData(n.id, 'prompt', e.target.value)} />
              )}
              {n.data.type === 'return' && (
                <TextField label="Value" fullWidth sx={{ mt: 1 }} value={String(n.data.value ?? '')} onChange={(e)=>updateNodeData(n.id, 'value', e.target.value)} />
              )}
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

