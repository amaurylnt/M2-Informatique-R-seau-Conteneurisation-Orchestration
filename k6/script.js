import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    rps: {
      executor: 'constant-arrival-rate',
      rate: 50,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 20,
      maxVUs: 50,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01'],
  },
};

export default () => {
  const res = http.get('http://workshop.local/status/200');
  check(res, { 'status 200': (r) => r.status === 200 });
};
