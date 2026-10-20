// k6 smoke/load test for Weather_API.
//   k6 run -e BASE=https://<host>/Weather_API/rest/v1 tests/load/smoke.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    browse: {
      executor: 'ramping-vus',
      stages: [{ duration: '1m', target: 20 }, { duration: '3m', target: 20 }, { duration: '30s', target: 0 }],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{name:snapshot}': ['p(95)<500'],
    'http_req_duration{name:series}': ['p(95)<800'],
  },
};

const BASE = __ENV.BASE;
const metrics = ['air-temperature', 'relative-humidity', 'wind-speed', 'rainfall'];

export default function () {
  const metric = metrics[Math.floor(Math.random() * metrics.length)];
  const snap = http.get(`${BASE}/snapshot?metric=${metric}`, { tags: { name: 'snapshot' } });
  check(snap, { 'snapshot 200': (r) => r.status === 200 });

  const stations = snap.json('stations') || [];
  if (stations.length) {
    const id = stations[Math.floor(Math.random() * stations.length)].id;
    const to = new Date();
    const from = new Date(to.getTime() - 24 * 3600 * 1000);
    const series = http.get(
      `${BASE}/stations/${id}/readings?metric=${metric}&from=${from.toISOString()}&to=${to.toISOString()}`,
      { tags: { name: 'series' } },
    );
    check(series, { 'series 200': (r) => r.status === 200 });
  }
  sleep(1 + Math.random() * 2);
}
