import 'dotenv/config';
import { footballApi } from '../src/lib/football-api';

async function testApi() {
  try {
    console.log("Testing API for season 2025...");
    const standings = await footballApi.getStandings('39', '2025');
    console.log("Standings 2025 length:", standings.length);
    if (standings.length === 0) {
      console.log("Empty. Let's try 2023...");
      const s2023 = await footballApi.getStandings('39', '2023');
      console.log("Standings 2023 length:", s2023.length);
    }
    process.exit(0);
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}

testApi();
