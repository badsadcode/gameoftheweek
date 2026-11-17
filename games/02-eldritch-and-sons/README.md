# ELDRITCH & SONS: Fine Goods & Curiosities

*Bad Ideas Works · Games of the Week · Week 2 · Theme: eldritch horror shop simulator*
*Concept: Tom's chaos, translated into human by Noor. Built by Sage.*

You inherited your grandfather's general store in an old, slightly peculiar town.
Running the shop should feel normal. The world around it becomes increasingly impossible.

## Controls

| Key | Action |
| --- | --- |
| WASD + mouse | Move and look |
| Shift | Run |
| E / left click | Use: pick up boxes, stock shelves, ring up customers, flip the sign, read letters |
| R / right click | Refuse a customer at the till, or pack a shelf back into a box |
| Q | Put a box down |
| Tab | Notebook (the shop rules) |
| Esc | Pause |

## A day at Eldritch & Sons
1. Read the letter on the doormat (new rules arrive most mornings).
2. Order stock from the catalogue on the counter: Ashford Wholesale delivers to the back door in
   about an hour; the Catalogue from Beyond delivers... somehow.
3. Carry boxes from the storeroom and stock the six shelves.
4. Flip the sign to OPEN. Customers browse, pick up what they want and queue at the till.
5. Ring them up. Or refuse them. Some customers come with rules, and the rules matter.
6. After 20:00, close up and go to bed in the storeroom. Nights are... eventful.

The Landlord collects $150 on Friday night. Keep your money up, your reputation up, and your
sanity above zero.

## Tech
- Engine: [Godot 4.4](https://godotengine.org) (GDScript, compatibility renderer).
- Everything is built in code: procedural 16×16 pixel textures, box-built world, articulated
  voxel characters (rigid parts on shoulder/elbow/hip/knee pivots), synthesized sound.
- The security camera is a second camera that can't see visual layer 2. Some customers live on layer 2.
- Fonts: Pixelify Sans and VT323 (SIL Open Font License, in `src/assets/fonts/`).
- Voices: the letters (Grandpa, the Supplier, the Landlord) were voiced by Tom with ElevenLabs
  (`src/assets/voice/`, loudness-matched OGG). They play when you read a letter; "Listen again"
  replays them, and they can be switched off in the pause menu.
- Art by Tom: pixel-art textures in `src/assets/textures/<name>.png` (walls, floors, street, products,
  faces, sign, catalogue, paper) override the generated ones by filename; product models in
  `src/assets/models/<product id>.glb` (any scale, auto-fitted to the shelf slot). Products with a
  texture but no model are shown as pixel cards; anything missing falls back to code-generated art.
  Keep `detect_3d/compress_to=0` in the texture `.import` files so pixel art stays lossless.
- `build.sh <out>` exports the Windows exe and the web build (downloads Godot + templates once).
- Test bot: `godot --path src -- --autotest [--day=N] [--min=M] [--quit-at=M] [--trace]`
  plays the week, follows the rules and saves screenshots to the user data folder.
