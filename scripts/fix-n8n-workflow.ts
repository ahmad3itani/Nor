/**
 * Fix n8n workflow: update Publish node bodyParametersJson format
 * and fix Format node image extraction.
 *
 * Usage:
 *   N8N_URL=https://n8n.srv1147752.hstgr.cloud N8N_KEY=<your-key> npx tsx scripts/fix-n8n-workflow.ts
 */

const N8N_URL = process.env.N8N_URL || 'https://n8n.srv1147752.hstgr.cloud';
const N8N_KEY = process.env.N8N_KEY;
const WORKFLOW_ID = 'xRlfGxJkVZhHA1dO';

if (!N8N_KEY) {
  console.error('Error: N8N_KEY environment variable is required');
  process.exit(1);
}

const headers = {
  'X-N8N-API-KEY': N8N_KEY,
  'Content-Type': 'application/json',
};

// The correct bodyParametersJson for the Publish node.
// Must start with "=" and use {{expression}} inside.
const PUBLISH_BODY_JSON = `={"title": "{{$json.title}}", "content": "{{$json.content}}", "excerpt": "{{$json.excerpt || ''}}", "category": "{{$json.category || 'general'}}", "teams": {{JSON.stringify($json.teams || [])}}, "tags": {{JSON.stringify($json.tags || [])}}, "image_url": "{{$('Format').item.json.image || ''}}", "source": "n8n-auto", "source_url": "{{$('Format').item.json.link || ''}}"}`;

async function main() {
  // 1. Fetch current workflow
  console.log(`Fetching workflow ${WORKFLOW_ID}...`);
  const getRes = await fetch(`${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}`, { headers });
  if (!getRes.ok) {
    const text = await getRes.text();
    console.error(`Failed to fetch workflow: ${getRes.status} ${text}`);
    process.exit(1);
  }
  const workflow = await getRes.json();
  console.log(`Got workflow: "${workflow.name}" with ${workflow.nodes?.length} nodes`);

  // 2. Find and fix the Publish node
  let publishFixed = false;
  let formatFixed = false;

  for (const node of workflow.nodes || []) {
    // Fix Publish node
    if (node.name === 'Publish' && node.type === 'n8n-nodes-base.httpRequest') {
      console.log('\nFixing Publish node...');
      console.log('Current bodyParametersJson:', JSON.stringify(node.parameters?.bodyParametersJson)?.slice(0, 100));

      node.parameters.bodyParametersJson = PUBLISH_BODY_JSON;
      // Ensure sendBody is true and body content type is JSON
      node.parameters.sendBody = true;
      node.parameters.bodyContentType = 'json';
      node.parameters.specifyBody = 'json';

      console.log('New bodyParametersJson:', PUBLISH_BODY_JSON.slice(0, 100) + '...');
      publishFixed = true;
    }

    // Fix Format node — function node that extracts image from RSS item
    if (node.name === 'Format' && node.type === 'n8n-nodes-base.function') {
      console.log('\nFixing Format node functionCode...');
      console.log('Current:', node.parameters?.functionCode?.slice(0, 100));

      node.parameters.functionCode = `return items.map(item => {
  const j = item.json;
  const html = j['content:encoded'] || j.content || j.contentSnippet || '';
  const imgMatch = html.match(/<img[^>]+src=["']([^"']+)["']/i);
  const mediaContent = j['media:content'];
  const mediaThumbnail = j['media:thumbnail'];
  const image =
    (Array.isArray(mediaContent) ? mediaContent[0] : mediaContent)?.['$']?.url ||
    (Array.isArray(mediaThumbnail) ? mediaThumbnail[0] : mediaThumbnail)?.['$']?.url ||
    j.enclosure?.url ||
    (imgMatch ? imgMatch[1] : null) ||
    '';
  return { json: { title: j.title, link: j.link, content: j.contentSnippet || j.content || '', image } };
});`;

      console.log('Updated Format node functionCode');
      formatFixed = true;
    }
  }

  if (!publishFixed) {
    console.error('\nWARNING: Publish node not found or not fixed!');
    const nodeNames = workflow.nodes?.map((n: any) => `${n.name} (${n.type})`).join(', ');
    console.log('Available nodes:', nodeNames);
  }

  if (!formatFixed) {
    console.log('\nFormat node image field not fixed (may not need it or field not found)');
  }

  // 3. PUT workflow back
  console.log('\nUpdating workflow...');
  // Only include settings fields accepted by n8n PUT API
  const putBody = {
    name: workflow.name,
    nodes: workflow.nodes,
    connections: workflow.connections,
    settings: { executionOrder: workflow.settings?.executionOrder || 'v1' },
    staticData: workflow.staticData || null,
  };

  const putRes = await fetch(`${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}`, {
    method: 'PUT',
    headers,
    body: JSON.stringify(putBody),
  });

  if (!putRes.ok) {
    const text = await putRes.text();
    console.error(`Failed to update workflow: ${putRes.status} ${text}`);
    process.exit(1);
  }

  const updated = await putRes.json();
  console.log(`\nWorkflow updated successfully: "${updated.name}"`);
  console.log('Active:', updated.active);
}

main().catch(e => { console.error(e); process.exit(1); });
