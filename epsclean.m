function epsclean( file, outfile, removeBoxes, groupSoft )
% EPSCLEAN Cleans up a MATLAB exported .eps file.
%
%   EPSCLEAN(F) cleans the .eps file F without removing box elements.
%   EPSCLEAN(F,O,R,G) cleans the .eps file F, writes the result to file O and optionally removes box elements if
%                     R = true. Optionally it groups elements 'softly' if G = true.
%
%   When exporting a figure with Matlab's 'saveas' function to vector graphics multiple things might occur:
%   - Paths are split up into multiple segments and white lines are created on patch objects
%     see https://de.mathworks.com/matlabcentral/answers/290313-why-is-vector-graphics-chopped-into-pieces
%   - There are unnecessary box elements surrounding the paths
%   - Lines which actually should be continuous are split up in small line segments
%
%   Especially the fragmentation is creating highly unusable vector graphics for further post-processing.
%   This function fixes already exported figures in PostScript file format by grouping paths together according to their
%   properties (line width, line color, transformation matrix, ...). Small line segments which logically should belong
%   together are replaced by one continous line.
%   It also removes paths with 're' (rectangle) elements when supplying the parameter 'removeBoxes' with true. The
%   default is false.
%   In case the 'groupSoft' parameter is true it does not group elements according to their properties over the whole
%   document. It will rather group them only if the same elements sequentially occur, but not if they are interrupted by
%   elements with different properties. This will result in more fragmentation, but the Z-order will be kept intact. The
%   default is false.
%
%   Example 1
%   ---------
%       z = peaks;
%       contourf(z);
%       print(gcf,'-depsc','-painters','out.eps');
%       epsclean('out.eps'); % cleans and overwrites the input file
%       epsclean('out.eps','clean.eps'); % leaves the input file intact
%       epsclean('out.eps','out.eps',true); % cleans and overwrites input file plus removes box elements
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
%   Changes
%   -------
%   2017-04-03 (YYYY-MM-DD)
%   - Line segments with the same properties are converted to one continous polyline
%      o As a side effect this will cause multiple equal lines on top of each other to merge
%   - The Z-order of elements can be preserved by using 'groupSoft = true'
%      o See https://github.com/Conclusio/matlab-epsclean/issues/6
%      o This will cause additional fragmentation which might or might not be what you want
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
if ~exist('groupSoft','var')
    groupSoft = false;
end

keepInput = exist('outfile','var');
if ~keepInput || strcmp(file, outfile)
    outfile = [file '_out']; % tmp file
    keepInput = false;
end

fid1 = fopen(file,'r');
fid2 = fopen(outfile,'w');

previousBlockPrefix = [];
currentBlockPrefix = [];
currentBlockContent = {};
currentBlockContentFull = {};
operation = -1; % -1 .. wait for 'EndPageSetup', 0 .. wait for blocks, 1 .. create id, 2 .. analyze block content, 3 .. analyzed
insideAxg = false;
blockGood = true;
hasLineCap = false;
blockList = [];
nested = 0;
lastMoveLine = [];
lastLineLine = [];
blockMap = containers.Map(); % blockPrefix -> MAP with nodeCount, adjMat, id2idxMap, idx2idMap

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
            if groupSoft && ~strcmp(currentBlockPrefix, previousBlockPrefix)
                % SOFT GROUPING. different block -> dump all existent ones except the current one

                currentBlock = [];
                if blockMap.isKey(currentBlockPrefix)
                    currentBlock = blockMap(currentBlockPrefix);
                    blockMap.remove(currentBlockPrefix);
                end
                
                writeBlocks(blockList, blockMap, fid2);
                
                blockList = [];
                blockMap = containers.Map();
                if ~isempty(currentBlock)
                    blockMap(currentBlockPrefix) = currentBlock;
                end
            end
            
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
        previousBlockPrefix = currentBlockPrefix;
        currentBlockPrefix = [];
    end


    if operation == 0 % waiting for blocks
        if ~isempty(regexp(thisLine, '^GS$', 'once'))
            % start of a block
            operation = 1;
            hasLineCap = false;
            nested = 0;
        elseif ~isempty(regexp(thisLine, '^%%Trailer$', 'once'))
            % end of figures -> dump all blocks
            writeBlocks(blockList, blockMap, fid2);
            fprintf(fid2, '%s\n', thisLine);
        elseif ~isempty(regexp(thisLine, '^GR$', 'once'))
            % unexpected GR before a corresponding GS -> ignore
        else
            % not inside a block and not the start of a block -> just take it
            fprintf(fid2, '%s\n', thisLine);
        end
    elseif operation == 1 % inside GS/GR block
        % build prefix
        if ~isempty(regexp(thisLine, '^%AXGBegin', 'once'))
            % this could be the beginning of a raw bitmap data block -> just take it
            insideAxg = true;
            currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
        elseif ~isempty(regexp(thisLine, '^%AXGEnd', 'once'))
            insideAxg = false;
            currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
        elseif insideAxg
            currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
        elseif ~isempty(regexp(thisLine, '^N$', 'once'))
            % begin analyzing
            operation = 2;
            blockGood = true;
            currentBlockContent = {};
            currentBlockContentFull = {};
            lastMoveLine = [];
            if ~blockMap.isKey(currentBlockPrefix)
                blockMap(currentBlockPrefix) = containers.Map(...
                    {'nodeCount','adjMat','id2idxMap','idx2idMap'},...
                    {0,false(100),containers.Map(),containers.Map('KeyType','uint32','ValueType','char')});
            end
        elseif ~isempty(regexp(thisLine, '^GS$', 'once'))
            nested = nested + 1;
            currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
        elseif ~isempty(regexp(thisLine, '^GR$', 'once'))
            nested = nested - 1;
            if nested >= 0
                currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
            else
                % end of block without a 'N' = newpath command
                % we don't know what it is, but we take it as a whole
                blockGood = true;
                currentBlockContent = {};
                currentBlockContentFull = {};
                operation = 3;
            end
        elseif ~isempty(regexp(thisLine, 'setlinecap$', 'once'))
            hasLineCap = true;
            currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
        elseif ~isempty(regexp(thisLine, 'LJ$', 'once'))
            if hasLineCap
                currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
            else
                % add '1 linecap' if no linecap is specified
                currentBlockPrefix = sprintf('%s%s\n%s\n',currentBlockPrefix,'1 setlinecap',thisLine);
            end
        else
            currentBlockPrefix = sprintf('%s%s\n',currentBlockPrefix, thisLine);
        end
    elseif operation == 2 % analyze block content
        if ~isempty(regexp(thisLine, '^%AXGBegin', 'once'))
            % this could be the beginning of a raw bitmap data block -> just take it
            insideAxg = true;
            currentBlockContent{end+1} = thisLine; %#ok<AGROW>
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
        elseif ~isempty(regexp(thisLine, '^%AXGEnd', 'once'))
            insideAxg = false;
            currentBlockContent{end+1} = thisLine; %#ok<AGROW>
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
        elseif insideAxg
            currentBlockContent{end+1} = thisLine; %#ok<AGROW>
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
        elseif ~isempty(regexp(thisLine, 're$', 'once'))
            if removeBoxes
                blockGood = false;
            else
                currentBlockContent{end+1} = thisLine; %#ok<AGROW>
                currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
            end
        elseif ~isempty(regexp(thisLine, '^clip$', 'once'))
            blockMap.remove(currentBlockPrefix);
            currentBlockPrefix = sprintf('%sN\n%s\n%s\n', currentBlockPrefix, strjoin(currentBlockContentFull,'\n'), thisLine);
            currentBlockContent = {};
            currentBlockContentFull = {};
            if ~blockMap.isKey(currentBlockPrefix)
                blockMap(currentBlockPrefix) = containers.Map(...
                    {'nodeCount','adjMat','id2idxMap','idx2idMap'},...
                    {0,false(100),containers.Map(),containers.Map('KeyType','uint32','ValueType','char')});
            end

        elseif ~isempty(regexp(thisLine, 'M$', 'once'))
            lastMoveLine = thisLine;
            nextline = fgetl(fid1); % ASSUMPTION: there is an L directly after an M
            lastLineLine = nextline;
            moveId = thisLine(1:end-1);
            lineId = nextline(1:end-1);
            addConnection(blockMap, currentBlockPrefix, moveId, lineId);
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
            currentBlockContentFull{end+1} = nextline; %#ok<AGROW>
        elseif ~isempty(regexp(thisLine, '^cp$', 'once'))
            moveId = lastLineLine(1:end-1);
            lineId = lastMoveLine(1:end-1);
            addConnection(blockMap, currentBlockPrefix, moveId, lineId);
            lastLineLine = lastMoveLine;
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
        elseif ~isempty(regexp(thisLine, 'L$', 'once'))
            moveId = lastLineLine(1:end-1);
            lineId = thisLine(1:end-1);
            addConnection(blockMap, currentBlockPrefix, moveId, lineId);
            lastLineLine = thisLine;
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
        elseif ~isempty(regexp(thisLine, '^f$', 'once'))
            % special handling for filled areas
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
            currentBlockContent = currentBlockContentFull;
            % remove all connections:
            b = blockMap(currentBlockPrefix);
            b('nodeCount') = 0; %#ok<NASGU>
        elseif ~isempty(regexp(thisLine, '^GS$', 'once'))
            nested = nested + 1;
            currentBlockContent{end+1} = thisLine; %#ok<AGROW>
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
        elseif ~isempty(regexp(thisLine, '^GR$', 'once'))
            % end of block content
            nested = nested - 1;
            if nested >= 0
                currentBlockContent{end+1} = thisLine; %#ok<AGROW>
            else
                operation = 3; % end of block content
            end
        else
            currentBlockContent{end+1} = thisLine; %#ok<AGROW>
            currentBlockContentFull{end+1} = thisLine; %#ok<AGROW>
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

function id = getNodeId(blockMap, blockId, nodeIndex)
    theblock = blockMap(blockId);
    themap = theblock('idx2idMap');
    id = themap(nodeIndex);
end

function index = getNodeIndex(blockMap, blockId, nodeId)
    theblock = blockMap(blockId);
    themap = theblock('id2idxMap');
    if themap.isKey(nodeId)
        index = themap(nodeId);
    else
        index = theblock('nodeCount') + 1;
        theblock('nodeCount') = index;
        themap(nodeId) = index; %#ok<NASGU>

        % other direction index -> id:
        themap2 = theblock('idx2idMap');
        themap2(index) = nodeId; %#ok<NASGU>
    end
end

function addConnection(blockMap, blockId, nodeId1, nodeId2)
    if strcmp(nodeId1, nodeId2)
        return; % ignore zero length lines
    end
    idx1 = getNodeIndex(blockMap, blockId, nodeId1);
    idx2 = getNodeIndex(blockMap, blockId, nodeId2);
    theblock = blockMap(blockId);
    count = theblock('nodeCount');

    adjMat = theblock('adjMat');
    adjSize = size(adjMat,1);

    if count > adjSize
        % resize adjacency matrix
        adjMat = [adjMat false(adjSize, 100)];
        adjMat = [adjMat ; false(100, adjSize+100)];
    end

    adjMat(idx1,idx2) = true;
    adjMat(idx2,idx1) = true;
    theblock('adjMat') = adjMat; %#ok<NASGU>
end

function writeBlocks(blockList, blockMap, fileId)
    for block = blockList
        fprintf(fileId, 'GS\n%s', block.prefix);
        if blockMap.isKey(block.prefix)
            b = blockMap(block.prefix);
            nodeCount = b('nodeCount');

            am = b('adjMat');
            am = am(1:nodeCount,1:nodeCount);
            connCount = sum(am,1);
            total = sum(connCount,2);

            if total == 0
                if ~isempty(block.content)
                    if isempty(regexp(block.prefix, sprintf('clip\n$'), 'once')) % prefix does not end with clip
                        fprintf(fileId, 'N\n');
                    end
                    for c = block.content
                        fprintf(fileId, '%s\n', cell2mat(c));
                    end
                end
            else
                fprintf(fileId, 'N\n');

                [~,sidx] = sort(connCount);
                for ni = sidx
                    firstNode = -1;
                    first = true;
                    search = true;
                    node = ni;

                    while(search)
                        neighbours = find(am(node,:));
                        search = false;
                        for nni = neighbours
                            if ~am(node,nni)
                                continue; % edge visited
                            end
                            if first
                                fprintf(fileId, '%sM\n', getNodeId(blockMap, block.prefix, node));
                                first = false;
                                firstNode = node;
                            end
                            am(node,nni) = false;
                            am(nni,node) = false;
                            if nni == firstNode
                                % closed path (polygon) -> use a 'closepath' command instead of a line
                                fprintf(fileId, 'cp\n');
                            else
                                fprintf(fileId, '%sL\n', getNodeId(blockMap, block.prefix, nni));
                            end
                            node = nni;
                            search = true;
                            break;
                        end
                    end
                end 

                for c = block.content
                    fprintf(fileId, '%s\n', cell2mat(c));
                end
            end
        end

        fprintf(fileId, 'GR\n');
    end
end

