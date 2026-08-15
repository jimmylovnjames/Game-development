# scenes/ui

HUD, journal, inventory and dialogue scenes. UI reads game state through
signals — it never drives gameplay systems directly.

`touch_controls.tscn` is the Android on-screen stick / look pad / action
buttons. The overlay builds its widgets in script so the scene file stays a
thin CanvasLayer.
