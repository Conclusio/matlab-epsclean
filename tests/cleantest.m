function cleantest()

addpath('../');
if ~isdir('results')
    mkdir('results');
end

fh = figure;
hold on;
colormap default;

% ------------------
% TEST: test case with one polygon having a 'self edge'.
% ------------------

copyfile('selfIntersect.eps', 'results/selfIntersect_out.eps');
tic;
epsclean('results/selfIntersect_out.eps','results/selfIntersect_clean.eps','combineAreas',true);
disp(toc);

% ------------------
% TEST: circular polygon with hole in the center
% ------------------
copyfile('circular.eps', 'results/circular_out.eps');
epsclean('results/circular_out.eps','results/circular_clean.eps');

% ------------------
% TEST: User 'morattico' test case
% ------------------

copyfile('fig1_original.eps', 'results/fig1_out.eps');
tic;
epsclean('results/fig1_out.eps','results/fig1_clean.eps','combineAreas',true);
disp(toc);
% (might need soft-grouping for z-order)

% ------------------
% TEST: InvertHardCopy
% ------------------
clf;
set(gcf,'Color','k');
set(gcf,'InvertHardCopy','off');
rectangle('Position',[1,1,2,2],'FaceColor','k','EdgeColor','g','LineWidth',5);
xlim([0,4]);
ylim([0,4]);
print(gcf,'-depsc','-painters','results/black_out.eps');
epsclean('results/black_out.eps','results/black_clean.eps','groupSoft',true);
close(fh);
fh = figure;
hold on;
colormap default;

% ------------------
% TEST: Z-Order test
% ------------------
clf;
rectangle('Position',[1,2,5,10],'FaceColor',[1 0 0],'EdgeColor','k','LineWidth',15);
rectangle('Position',[3,4,5,10],'FaceColor',[0 1 0],'EdgeColor','k','LineWidth',15);
rectangle('Position',[5,6,5,10],'FaceColor',[1 0 0],'EdgeColor','k','LineWidth',15);
print(gcf,'-depsc','-painters','results/area1_out.eps');
tic;
epsclean('results/area1_out.eps','results/area1_clean.eps','groupSoft',true); % NEEDS SOFT GROUPING!!
disp(toc);

% ------------------
% TEST: One continous (3D) line is hacked up by Matlab, but is restored by epsclean
% ------------------
clf;
x = [760,760,756,755,755,753,748,745,745,743,738,736,735,731,729,728,727,726,726,725,720,719,718,718,715,714,713,712,712,709,706,701,700,698,697,696,694,694,689,689,686,682,678,675,672,672,672,671,670,670,670,669,669,669,669,669,669,669,670,670,671,672,672,674,674,675,679,680,683,684,696,697,697];
y = [1101,1101,1102,1102,1102,1102,1103,1103,1104,1104,1105,1106,1106,1108,1108,1108,1108,1108,1108,1108,1110,1110,1110,1111,1113,1113,1113,1112,1112,1113,1114,1117,1118,1120,1121,1121,1122,1122,1126,1127,1130,1135,1140,1145,1150,1150,1150,1154,1156,1157,1158,1165,1167,1167,1171,1174,1183,1185,1186,1190,1193,1203,1206,1211,1212,1213,1225,1228,1234,1238,1256,1257,1257];
z = [6426,6426,6426,6426,6426,6426,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6425,6426,6426,6426,6426,6426,6426];

plot3(x/100,y/100,z/100,'lineWidth',0.8,'color',[0,0.5,1]);
view([0.0124413699949245,0.00718302831565741,-0.999896802883611]);
axis off; axis tight; zlim([-100, 100]);
print(gcf,'-depsc','-painters','results/line1_out.eps');
tic;
epsclean('results/line1_out.eps','results/line1_clean.eps');
disp(toc);

% ------------------
% TEST: Export of binary images in .eps file + Z-Order problems
% ------------------
clf;
load handel.mat;
spectrogram(y,128,120,128,Fs);
print(gcf,'-depsc','-painters','results/handel_out.eps');
tic;
epsclean('results/handel_out.eps','results/handel_clean.eps','groupSoft',true); % NEEDS SOFT GROUPING!!
disp(toc);

% ------------------
% TEST: White line artefacts
% ------------------
clf;
z = peaks;
contourf(z);
print(gcf,'-depsc','-painters','results/test1_out.eps');
tic;
epsclean('results/test1_out.eps','results/test1_clean.eps');
disp(toc);

% ------------------
% TEST: White line artefacts + quite big (file size ~ 1.7 MB)
% ------------------
clf;
[X,Y,Z] = peaks(100);
[~,ch] = contourf(X,Y,Z);
ch.LineStyle = 'none';
ch.LevelStep = ch.LevelStep/10;
colormap('hot')
saveas(gcf, 'results/test2_out.eps', 'epsc');
tic;
epsclean('results/test2_out.eps','results/test2_clean.eps');
disp(toc);

close(fh);

end

