// Care scenes opened by the room's Feed / Play / Wash / Medicine buttons.
import { KitchenScene } from './kitchen.js';
import { YardScene } from './yard.js';
import { BathScene } from './bath.js';
import { NurseScene } from './nurse.js';

export const CARE_SCENES = { feed: KitchenScene, play: YardScene, wash: BathScene, medicine: NurseScene };
