# Fixing Matlab Vector Graphics Output
Clean/Repair .eps PostScript vector graphic files created by Matlab R2016b.
* Paths are grouped together according to their properties
* White line artifacts are fixed
* Broken up polylines are connected back together if they share the same properties (good for post-processing in Illustrator/Inkscape/etc.)
* Adjacent polygons of the same type are merged together (use parameter 'combineAreas')

## Related

* [Why is vector graphics chopped into pieces?](https://de.mathworks.com/matlabcentral/answers/290313-why-is-vector-graphics-chopped-into-pieces)
* [Lines on Patch-Objects after *.EPS/PDF export - e.g. with contourf](https://github.com/altmany/export_fig/issues/44)

## Example

Here is an example of what the .eps file looks before and after fixing it:

```
%%% Matlab Code
z = peaks;
contourf(z);
print(gcf,'-depsc','-painters','out.eps');
epsclean('out.eps'); % cleans and overwrites the input file
```

![Before and After](http://i.imgur.com/NRCnQiH.png)
**Layer count in Adobe Illustrator: 789 (before) vs. 30 (after)**

## Another Example

```
%%% Matlab Code
[X,Y,Z] = peaks(100);
[~,ch] = contourf(X,Y,Z);
ch.LineStyle = 'none';
ch.LevelStep = ch.LevelStep/10;
colormap('hot')
saveas(gcf, 'out.eps', 'epsc');
epsclean('out.eps'); % cleans and overwrites the input file
```

![Before and After](http://i.imgur.com/ag8LV7i.png)
**Layer count in Adobe Illustrator: 11,775 (before) vs. 76 (after)**

## Notes

* If you experience Z-order problems (i.e. the overlappings of your graphics change) try using parameter 'groupSoft' = true.
```
%%% Matlab Code
epsclean('out.eps',false,true); % the third parameter is for Z-order problems
```

* Have a look at the tests/cleantest.m script for test cases and examples
* Report any problems here at github with your examples (code or .eps file). I try my best to fix them
