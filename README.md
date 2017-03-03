# Fixing Matlab Vector Graphics Output
Clean/Repair .eps PostScript vector graphic files created by Matlab R2016b.
* Paths are grouped together according to their properties
* White line artifacts are fixed

# Example

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

# Another Example

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
