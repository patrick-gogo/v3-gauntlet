// Turn the plugin's markdown (tickets, plans, rulings, handoffs) into Notion blocks.
// Deliberately small: headings (#### and deeper become heading_3), paragraphs, lists (nesting is flattened), quotes, dividers, fenced code,
// inline **bold** and `code`; tables become code blocks.
const LIMIT = 2000;
const LANGS = { js: 'javascript', javascript: 'javascript', ts: 'typescript', typescript: 'typescript', tsx: 'typescript',
  bash: 'bash', sh: 'shell', shell: 'shell', python: 'python', py: 'python', json: 'json', sql: 'sql', yaml: 'yaml',
  md: 'markdown', markdown: 'markdown', html: 'html', css: 'css', diff: 'diff' };

const MAX_ITEMS = 100;
const pieces = (content, annotations) => {
  const out = [];
  for (let i = 0; i < content.length; i += LIMIT) {
    const t = { type: 'text', text: { content: content.slice(i, i + LIMIT) } };
    if (annotations) t.annotations = annotations;
    out.push(t);
  }
  return out;
};
// Inline **bold** and `code` become annotations when inline is true; code blocks keep their text verbatim.
function rich(text, inline) {
  const out = [];
  if (!inline) out.push(...pieces(text));
  else {
    const re = /\*\*(.+?)\*\*|`([^`]+)`/g;
    let last = 0, m;
    while ((m = re.exec(text))) {
      if (m.index > last) out.push(...pieces(text.slice(last, m.index)));
      out.push(...pieces(m[1] ?? m[2], m[1] !== undefined ? { bold: true } : { code: true }));
      last = re.lastIndex;
    }
    if (last < text.length) out.push(...pieces(text.slice(last)));
  }
  return out.length ? out : [{ type: 'text', text: { content: '' } }];
}
// Notion allows 100 rich_text items per block, so a longer run is split into several blocks of the same type.
function block(type, text, extra = {}, inline = true) {
  const items = rich(text, inline), res = [];
  for (let i = 0; i < items.length; i += MAX_ITEMS) res.push({ object: 'block', type, [type]: { rich_text: items.slice(i, i + MAX_ITEMS), ...extra } });
  return res;
}

export function markdownToBlocks(md) {
  const lines = String(md).replace(/\r\n/g, '\n').split('\n');
  const blocks = [];
  let para = [];
  const flush = () => { if (para.length) { blocks.push(...block('paragraph', para.join(' '))); para = []; } };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const fence = line.match(/^```\s*(\S*)\s*$/);
    if (fence) {
      flush();
      const body = [];
      while (++i < lines.length && !/^```\s*$/.test(lines[i])) body.push(lines[i]);
      // An unclosed fence runs to the end of the file and is still emitted as a code block.
      blocks.push(...block('code', body.join('\n'), { language: LANGS[fence[1].toLowerCase()] || 'plain text' }, false));
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      flush();
      const rows = [line];
      while (i + 1 < lines.length && /^\s*\|.*\|\s*$/.test(lines[i + 1])) rows.push(lines[++i]);
      blocks.push(...block('code', rows.join('\n'), { language: 'plain text' }, false));
      continue;
    }
    let m;
    if (line.trim() === '') { flush(); continue; }
    if (/^(---|\*\*\*)\s*$/.test(line)) { flush(); blocks.push({ object: 'block', type: 'divider', divider: {} }); continue; }
    if ((m = line.match(/^(#{1,6})\s+(.*)$/))) { flush(); blocks.push(...block(`heading_${Math.min(m[1].length, 3)}`, m[2])); continue; }
    if ((m = line.match(/^\s*[-*]\s+(.*)$/))) { flush(); blocks.push(...block('bulleted_list_item', m[1])); continue; }
    if ((m = line.match(/^\s*\d+[.)]\s+(.*)$/))) { flush(); blocks.push(...block('numbered_list_item', m[1])); continue; }
    if ((m = line.match(/^>\s?(.*)$/))) { flush(); blocks.push(...block('quote', m[1])); continue; }
    para.push(line.trim());
  }
  flush();
  return blocks;
}
