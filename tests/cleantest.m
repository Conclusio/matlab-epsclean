function cleantest()

addpath('../');
if ~isdir('results')
    mkdir('results');
end

% ------------------
load handel.mat;
spectrogram(y,128,120,128,Fs);
print(gcf,'-depsc','-painters','results/handel_out.eps');
epsclean('results/handel_out.eps','results/handel_clean.eps');

% ------------------
z = peaks;
contourf(z);
print(gcf,'-depsc','-painters','results/test1_out.eps');
epsclean('results/test1_out.eps','results/test1_clean.eps');

% ------------------
[X,Y,Z] = peaks(100);
[~,ch] = contourf(X,Y,Z);
ch.LineStyle = 'none';
ch.LevelStep = ch.LevelStep/10;
colormap('hot')
saveas(gcf, 'results/test2_out.eps', 'epsc');
epsclean('results/test2_out.eps','results/test2_clean.eps');
end

