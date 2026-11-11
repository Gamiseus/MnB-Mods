# TrueSight

The game's `los` and `los2` are answered by casting a ray against the real shapes of trees, rocks, buildings, smoke and vehicles (LÖVE's Box2D), in place of the game's sampled check. This changes who can see and shoot whom. The game's own checks stay available as `vanilla_los` and `vanilla_los2`. F10 shows the obstacles and rays.

For other mods, the global `los_physics`: `checkLOS(x1, x2, y1, y2)`, `checkLOS2(shooter, target)`, `castRay(x1, y1, x2, y2, opts)`, `computeVisionPolygon(originX, originY, maxRange, numRays, opts)`.
