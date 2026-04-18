import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    openapi: '3.0.0',
    info: { title: 'Market Trigger API', version: '1.0.0', description: 'Agent-ready market trigger API for automated trading decisions' },
    servers: [{ url: 'https://market-trigger-api.onrender.com' }],
    paths: {
      '/v1/trigger': {
        post: {
          summary: 'Evaluate trigger conditions against market context',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: ['asset', 'conditions', 'context'],
                  properties: {
                    asset: { type: 'string', example: 'BTC' },
                    conditions: { type: 'object' },
                    context: { type: 'object' }
                  }
                }
              }
            }
          },
          responses: {
            '200': { description: 'Trigger evaluation response' },
            '400': { description: 'Invalid request' },
            '500': { description: 'Server error' }
          }
        }
      },
      '/v1/health': {
        get: { summary: 'Health check', responses: { '200': { description: 'OK' } } }
      }
    }
  });
});

export default router;
