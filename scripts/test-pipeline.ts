import { runNewsPipeline } from '../src/lib/pipeline';

console.log("Populating DB with fresh news from RSS + OpenRouter...");
runNewsPipeline().then((res) => {
  console.log("Pipeline executed successfully:", res);
  process.exit(0);
}).catch(e => {
  console.error("Failed pipeline:", e);
  process.exit(1);
});
