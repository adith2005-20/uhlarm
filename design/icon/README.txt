uhlarm app icon (Rising edge)

Quick route (Xcode asset catalog, AppIcon, single size):
  AppIcon-1024.png         -> Any appearance
  AppIcon-1024-dark.png    -> Dark appearance
  AppIcon-1024-tinted.png  -> Tinted appearance (white on transparent; iOS applies the tint)

Liquid Glass route (Icon Composer, comes with Xcode):
  layers/1-background-*  -> background
  layers/2-sun-*         -> group, glass off
  layers/3-ripples-*     -> group, glass on
  Use the -dawn files for Default and the -night files for Dark. Export the .icon and add it to the project.
