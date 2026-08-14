export type Block = {
  entity: string | null;
  start_offset: number;
  duration: number;
};

export type EntityTotal = {
  entity: string;
  seconds: number;
};

export type Lane = {
  source: string;
  kind: "session" | "counter";
  total_seconds: number;
  blocks: Block[];
  top_entities: EntityTotal[];
  connected: boolean;
};

export type DayView = {
  date: string;
  lanes: Lane[];
  total_seconds: number;
};
