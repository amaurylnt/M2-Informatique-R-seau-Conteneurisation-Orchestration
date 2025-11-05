// Simple OpenTelemetry auto-instrumentation for Node.js API -> Jaeger
// Usage locally: node -r ./tracing.js server.js
// In K8s, you can set env NODE_OPTIONS="-r ./tracing.js"
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

const exporter = new OTLPTraceExporter({
  // Jaeger OTLP gRPC collector inside cluster
  // For local dev (port-forward), you could use: 'grpc://localhost:4317'
  url: 'grpc://simplest-collector.observability:4317'
});

const sdk = new NodeSDK({
  traceExporter: exporter,
  instrumentations: [getNodeAutoInstrumentations()]
});

sdk.start().then(() => {
  console.log('OTel SDK started');
}).catch((err) => {
  console.error('Error starting OTel SDK', err);
});
