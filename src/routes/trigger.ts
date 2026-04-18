import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { evaluateTrigger } from '../services/triggerEngine';
import { logger } from '../middleware/logger';

const router = Router();

const schema = Joi.object({
  asset: Joi.string().min(1).max(20).uppercase().required(),
  conditions: Joi.object({
    min_impact_score: Joi.number().min(0).max(100).optional(),
    max_impact_score: Joi.number().min(0).max(100).optional(),
    action_bias: Joi.alternatives().try(
      Joi.string(),
      Joi.array().items(Joi.string())
    ).optional(),
    sentiment: Joi.alternatives().try(
      Joi.string(),
      Joi.array().items(Joi.string())
    ).optional(),
    min_confidence: Joi.number().min(0).max(1).optional(),
    event_types: Joi.array().items(Joi.string()).optional(),
    impact_horizon: Joi.alternatives().try(
      Joi.string(),
      Joi.array().items(Joi.string())
    ).optional(),
    freshness: Joi.alternatives().try(
      Joi.string(),
      Joi.array().items(Joi.string())
    ).optional(),
    require_risk_warning: Joi.boolean().optional(),
    forbid_risk_warning: Joi.boolean().optional()
  }).min(1).required(),
  context: Joi.object({
    news_impact: Joi.object().optional(),
    market_signal: Joi.object().optional()
  }).min(1).required()
});

router.post('/', async (req: Request, res: Response): Promise<void> => {
  const { error, value } = schema.validate(req.body);
  if (error) {
    res.status(400).json({ error: 'Invalid request', message: error.details[0].message });
    return;
  }

  try {
    const result = evaluateTrigger(value);
    res.json(result);
  } catch (err: any) {
    const msg: string = err.message || 'Unknown error';
    logger.error({ asset: value.asset, msg }, 'Trigger error');
    res.status(500).json({ error: 'Internal server error', message: msg });
  }
});

export default router;
