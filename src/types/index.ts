export interface TriggerConditions {
  min_impact_score?: number;
  max_impact_score?: number;
  action_bias?: string | string[];
  sentiment?: string | string[];
  min_confidence?: number;
  event_types?: string[];
  impact_horizon?: string | string[];
  freshness?: string | string[];
  require_risk_warning?: boolean;
  forbid_risk_warning?: boolean;
}

export interface NewsImpactContext {
  asset?: string;
  sentiment?: string;
  impact_score?: number;
  impact_horizon?: string;
  action_bias?: string;
  confidence?: number;
  event_type?: string;
  consensus?: string;
  freshness?: string;
  risk_warning?: string | null;
  drivers?: string[];
  watch_items?: string[];
}

export interface MarketSignalContext {
  asset?: string;
  decision?: string;
  confidence?: number;
  risk?: string;
  verdict?: string;
  trend?: string;
  momentum?: string;
}

export interface TriggerContext {
  news_impact?: NewsImpactContext;
  market_signal?: MarketSignalContext;
}

export interface TriggerRequest {
  asset: string;
  conditions: TriggerConditions;
  context: TriggerContext;
}

export interface TriggerResponse {
  asset: string;
  trigger: boolean;
  urgency: 'high' | 'medium' | 'low' | 'none';
  recommended_action: string;
  reason: string;
  conditions_met: string[];
  conditions_failed: string[];
  score: number;
  analyzedAt: string;
}
