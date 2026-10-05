// Turn the plugin's markdown (tickets, plans, rulings, handoffs) into Notion blocks.
// Deliberately small: headings, paragraphs, lists, quotes, dividers, fenced code; tables become code blocks.
const LIMIT = 2000;
const LANGS = { js: 'javascript', javascript: 'javascript', ts: 'typescript', typescript: 'typescript', tsx: 'typescript',
  bash: 'bash', sh: 'shell', shell: 'shell', python: 'python', py: 'python', json: 'json', sql: 'sql', yaml: 'yaml',
  md: 'markdown', markdown: 'markdown', html: 'html', css: 'css', diff: 'diff' };

function rich(text) {
  const out = [];
  for (let i = 0; i < text.length; i += LIMIT) out.push({ type: 'text', text: { content: text.slice(i, i + LIMIT) } });
  return out.length ? out : [{ type: 'text', text: { content: '' } }];
}
const block = (type, text, extra = {}) => ({ object: 'block', type, [type]: { rich_text: rich(text), ...extra } });

export function markdownToBlocks(md) {
  const lines = String(md).replace(/\r\n/g, '\n').split('\n');
  const blocks = [];
  let para = [];
  const flush = () => { if (para.length) { blocks.push(block('paragraph', para.join(' '))); para = []; } };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const fence = line.match(/^```\s*(\S*)\s*$/);
    if (fence) {
      flush();
      const body = [];
      while (++i < lines.length && !/^```\s*$/.test(lines[i])) body.push(lines[i]);
      blocks.push(block('code', body.join('\n'), { language: LANGS[fence[1].toLowerCase()] || 'plain text' }));
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      flush();
      const rows = [line];
      while (i + 1 < lines.length && /^\s*\|.*\|\s*$/.test(lines[i + 1])) rows.push(lines[++i]);
      blocks.push(block('code', rows.join('\n'), { language: 'plain text' }));
      continue;
    }
    let m;
    if (line.trim() === '') { flush(); continue; }
    if (/^(---|\*\*\*)\s*$/.test(line)) { flush(); blocks.push({ object: 'block', type: 'divider', divider: {} }); continue; }
    if ((m = line.match(/^(#{1,3})\s+(.*)$/))) { flush(); blocks.push(block(`heading_${m[1].length}`, m[2])); continue; }
    if ((m = line.match(/^\s*[-*]\s+(.*)$/))) { flush(); blocks.push(block('bulleted_list_item', m[1])); continue; }
    if ((m = line.match(/^\s*\d+[.)]\s+(.*)$/))) { flush(); blocks.push(block('numbered_list_item', m[1])); continue; }
    if ((m = line.match(/^>\s?(.*)$/))) { flush(); blocks.push(block('quote', m[1])); continue; }
    para.push(line.trim());
  }
  flush();
  return blocks;
}
