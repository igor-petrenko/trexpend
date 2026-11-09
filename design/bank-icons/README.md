# Bank Logo References

Design references only. These files are not application target resources.
Bank names and logos identify their respective brands; original ownership remains
with the respective owners. Retrieval is not a grant of redistribution rights.

| File | Source | Notes |
| --- | --- | --- |
| privatbank.svg | User-supplied SVG from PrivatBank's website | Preserve the green and black artwork on a light surface. |
| cibc.svg | https://www.cibc.com/content/dam/global-assets/logos/cibc-logos/no-tagline/cibc-logo-colour-142x36.svg | Official full-color wordmark, linked from the personal banking home page. |
| monobank.png | https://monobank.ua/assets/icon-CZao4z2I.png | Official website icon, 256 by 256 pixels, linked from the home page. |

Retrieved CIBC and monobank assets on 2026-11-08. Preserve SVG sources; prepare
compatible vector or raster asset-catalog resources during implementation. Do not
add an SVG runtime library. Use a light backing surface where needed for contrast.
The compact CIBC emblem can be prepared from its official vector artwork rather
than compressing the wide wordmark into a square. No runtime download is planned.


## Application Resources

Runtime PNG copies now live in the iOS asset catalog as bank_privatbank,
bank_cibc, and bank_monobank. PrivatBank was rasterized from the supplied SVG.
CIBC uses the two emblem paths from the official wordmark, retaining its colors
and proportions. monobank retains the official square website icon. SVG rendering
used native AppKit during asset preparation, with no added runtime dependency.
