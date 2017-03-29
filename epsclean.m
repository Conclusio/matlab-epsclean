function epsclean( file, outfile, removeBoxes )
%EPSCLEAN(F,O,R) Cleans up a Matlab exported .eps file.
%
%   EPSCLEAN(F) cleans the .eps file F without removing box elements.
%   EPSCLEAN(F,O,R) cleans the .eps file F, writes the result to file O and optionally removes box elements if R = true.
%
%   When exporting a figure with Matlab's 'saveas' function to vector graphics multiple things might occur:
%   - Paths are split up into multiple segments and white lines are created on patch objects
%     see https://de.mathworks.com/matlabcentral/answers/290313-why-is-vector-graphics-chopped-into-pieces
%   - There are unnecessary box elements surrounding the paths
%
%   Especially the fragmentation is creating highly unusable vector graphics for further post-processing.
%   This function fixes already exported figures in PostScript file format by grouping paths together according to their
%   properties (line width, line color, transformation matrix, ...).
%   It also removes paths with 're' (rectangle) elements when supplying the parameter 'removeBoxes' with true.
%
%   Example 1
%   ---------
%       z = peaks;
%       contourf(z);
%       print(gcf,'-depsc','-painters','out.eps');
%       epsclean('out.eps'); % cleans and overwrites the input file
%       %epsclean('out.eps','clean.eps'); % leaves the input file intact
%       %epsclean('out.eps','out.eps',true); % cleans and overwrites input file plus removes box elements
%
%   Example 2
%   ---------
%       [X,Y,Z] = peaks(100);
%       [~,ch] = contourf(X,Y,Z);
%       ch.LineStyle = 'none';
%       ch.LevelStep = ch.LevelStep/10;
%       colormap('hot')
%       saveas(gcf, 'out.eps', 'epsc');
%       epsclean('out.eps');
%
%   Notes
%   -----
%   - A block is a starting with GS (gsave) and ends with GR (grestore)
%   - Only text after %%EndPageSetup is analyzed
%   - Removing boxes will also remove the clipping area (if any)
%   - Tested on Windows with Matlab R2016b
%
%   ------------------------------------------------------------------------------------------
%   Copyright 2017, Stefan Spelitz, Vienna University of Technology (TU Wien).
%   This code is distributed under the terms of the GNU Lesser General Public License (LGPL).
%
%   This program is free software: you can redistribute it and/or modify
%   it under the terms of the GNU Lesser General Public License as published by
%   the Free Software Foundation, either version 3 of the License, or
%   (at your option) any later version.
% 
%   This program is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%   GNU Lesser General Public License for more details.
% 
%   You should have received a copy of the GNU Lesser General Public License
%   along with this program.  If not, see <http://www.gnu.org/licenses/>.

if ~exist('removeBoxes','var')
    removeBoxes = false;
end

keepInput = exist('outfile','var');
if ~keepInput || strcmp(file, outfile)
    outfile = [file '_out']; % tmp file
    keepInput = false;
end

fid1 = fopen(file,'r');
fid2 = fopen(outfile,'w');

currentBlockPrefix = [];
currentBlockContent = {};
operation = -1; % -1 .. wait for 'EndPageSetup', 0 .. wait for blocks, 1 .. create id, 2 .. analyze block content, 3 .. analyzed
blockGood = true;
blockList = [];
nested = 0;

while ~feof(fid1)
    thisLine = fgetl(fid1);

    % normal read until '%%EndPageSetup'
    if operation == -1
        if ~isempty(regexp(thisLine, '^%%EndPageSetup$', 'once'))
            operation = 0;
        end
        fprintf(fid2, '%s\n', thisLine);
        continue;
    end

    if operation == 3 % block was analyzed
        if blockGood
            blockIdx = 0;
            for ii = 1:length(blockList)
                block = blockList(ii);
                if strcmp(block.prefix, currentBlockPrefix)
                    blockIdx = ii;
                    break;
                end
            end

            if blockIdx == 0
                % new block
                block = struct();
                block.prefix = currentBlockPrefix;
                block.content = currentBlockContent;
                blockList = [blockList block]; %#ok<AGROW>
            else
                startIdx = length(blockList(blockIdx).content);
                lc = length(currentBlockContent);
                for ii = startIdx:(startIdx+lc-1)
                    blockList(blockIdx).content{ii} = currentBlockContent{ii-startIdx+1}; %#ok<AGROW>
                end
            end
        end
        operation = 0;
        currentBlockPrefix = [];
    end


    if operation == 0 % waiting for blocks
        if ~isempty(regexp(thisLine, '^GS$', 'once'))
            % start of a block
            operation = 1;
        elseif ~isempty(regexp(thisLine, '^%%Trailer$', 'once'))
            % end of figures -> dump all blocks

            for block = blockList
                fprintf(fid2, 'GS\n%s', block.prefix);
                if ~isempty(block.content)
                    fprintf(fid2, 'N\n');
                    for c = block.content
                        fprintf(fid2, '%s\n', cell2mat(c));
                    end
                end
                fprintf(fid2, 'GR\n');
            end

            fprintf(fid2, '%s\n', thisLine);
        elseif ~isempty(regexp(thisLine, '^GR$', 'once'))
            % unexpected GR before a corresponding GS -> ignore
        else
            % not inside a block and not the start of a block -> just take it
            fprintf(fid2, '%s\n', thisLine);
        end
    elseif operation == 1 % inside GS/GR block
        % build prefix
        if ~isempty(regexp(thisLine, '^N$', 'once'))
            % begin analyzing
            operation = 2;
            blockGood = true;
            currentBlockContent = {};
        elseif ~isempty(regexp(thisLine, '^GS$', 'once'))
            nested = nested + 1;
            currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
        elseif ~isempty(regexp(thisLine, '^GR$', 'once'))
            if nested > 0
                nested = nested - 1;
                currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine); 
            else
                % end of block without a 'N' = newpath command
                % we don't know what it is, but we take it as a whole
                blockGood = true;
                currentBlockContent = {};
                operation = 3;
            end
        else
            currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
        end
    elseif operation == 2 % analyze block content
        if ~isempty(regexp(thisLine, 're$', 'once'))
            if removeBoxes
                blockGood = false;
            else
                currentBlockContent{end+1} = thisLine; %#ok<AGROW>
            end
        elseif ~isempty(regexp(thisLine, 'M$', 'once'))
            % there should be a L after M
            nextline = fgetl(fid1);
            if ~isempty(regexp(nextline, 'L$', 'once'))
                if strcmp(thisLine(1:end-1),nextline(1:end-1))
                    % move and thisLine statement are the same -> basically a zero point, we don't want that
                    blockGood = false;
                end
            end

            currentBlockContent{end+1} = thisLine; %#ok<AGROW>
            currentBlockContent{end+1} = nextline; %#ok<AGROW>

        elseif ~isempty(regexp(thisLine, '^GR$', 'once'))
            % end of block content
            operation = 3;
        else
            currentBlockContent{end+1} = thisLine; %#ok<AGROW>
        end
    end

end %while

fclose(fid1);
fclose(fid2);

if ~keepInput
    delete(file);
    movefile(outfile, file);
end

end

