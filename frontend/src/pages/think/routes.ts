export const THINK_PROMPTS_PATH = '/engines/tools/prompts';
export const THINK_PROMPTS_NEW_PATH = `${THINK_PROMPTS_PATH}/new`;
export const THINK_PROMPTS_EDIT_PATTERN = '/engines/tools/prompts/edit/:version';
export const thinkPromptsEditPath = (version: string) => `/engines/tools/prompts/edit/${version}`;
