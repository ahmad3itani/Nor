import { initDb } from '../src/lib/db';

async function main() {
  console.log('Initializing database...');
  await initDb();
  console.log('Database initialized successfully.');
}

main().catch((e) => { console.error('Error initializing database:', e); process.exit(1); });
