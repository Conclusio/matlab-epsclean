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
fid2 = fopen(outfile,'W');

previousBlockPrefix = [];
operation = -1; % -1 .. wait for 'EndPageSetup', 0 .. wait for blocks, 1 .. create id, 2 .. analyze block content, 3 .. analyzed
insideAxg = false;
blockGood = true;
hasLineCap = false;
blockList = [];

nested = 0;
lastMoveLine = [];
lastLineLine = [];
blockMap = containers.Map(); % blockPrefix -> MAP with nodeCount, adjMat, id2idxMap, idx2idArray

% current block data:
cbNewBlock = false;
cbNodeCount = [];
cbAdjMat = [];
cbId2idxMap = [];
cbIdx2idArray  = [];
cbPrefix = [];
cbContentLines = -ones(1,100);
cbContentLinesFull = -ones(1,100);
cbContentLinesIdx = 1;
cbContentLinesFullIdx = 1;

% load whole file into memory:
fileContent = textscan(fid1,'%s','delimiter','\n');
fileContent = fileContent{1};
lineCount = length(fileContent);
lineIdx = 0;

while lineIdx < lineCount
    lineIdx = lineIdx + 1;
    thisLine = cell2mat(fileContent(lineIdx));
    
    % normal read until '%%EndPageSetup'
    if operation == -1
        if equalsWith(thisLine, '%%EndPageSetup')
            operation = 0;
            fprintf(fid2, '%s\n', strjoin(fileContent(1:lineIdx),'\n')); % dump prolog
        end
        continue;
    end
    
    if operation == 3 % block was analyzed
        if blockGood
            if groupSoft && ~strcmp(cbPrefix, previousBlockPrefix)
                % SOFT GROUPING. different block -> dump all existent ones except the current one

                currentBlock = [];
                if blockMap.isKey(cbPrefix)
                    currentBlock = blockMap(cbPrefix);
                    blockMap.remove(cbPrefix);
                end
                
                writeBlocks(blockList, blockMap, fid2, fileContent);
                
                blockList = [];
                blockMap = containers.Map();
                if ~isempty(currentBlock)
                    blockMap(cbPrefix) = currentBlock;
                end
            end

            setBlockData(blockMap,cbPrefix,cbNodeCount,cbAdjMat,cbId2idxMap,cbIdx2idArray,cbContentLines(1:cbContentLinesIdx-1));
            if cbNewBlock
                % new block
                block = struct('prefix', cbPrefix);
                blockList = [blockList block]; %#ok<AGROW>
            end
        end
        operation = 0;
        previousBlockPrefix = cbPrefix;
        cbPrefix = [];
    end


    if operation == 0 % waiting for blocks
        if equalsWith(thisLine,'GS')
            % start of a block
            operation = 1;
            hasLineCap = false;
            nested = 0;
        elseif equalsWith(thisLine,'%%Trailer')
            % end of figures -> dump all blocks
            writeBlocks(blockList, blockMap, fid2, fileContent);
            fprintf(fid2, '%s\n', thisLine);
        elseif equalsWith(thisLine,'GR')
            % unexpected GR before a corresponding GS -> ignore
        else
            % not inside a block and not the start of a block -> just take it
            fprintf(fid2, '%s\n', thisLine);
        end
    elseif operation == 1 % inside GS/GR block
        % build prefix
        if startsWith(thisLine,'%AXGBegin')
            % this could be the beginning of a raw bitmap data block -> just take it
            insideAxg = true;
            cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
        elseif startsWith(thisLine,'%AXGEnd')
            insideAxg = false;
            cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
        elseif insideAxg
            cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
        elseif equalsWith(thisLine,'N')
            % begin analyzing
            operation = 2;
            blockGood = true;
            cbContentLinesIdx = 1;
            cbContentLinesFullIdx = 1;
            lastMoveLine = [];
            [cbNodeCount,cbAdjMat,cbId2idxMap,cbIdx2idArray,cbNewBlock] = getBlockData(blockMap,cbPrefix);
        elseif equalsWith(thisLine,'GS')
            nested = nested + 1;
            cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
        elseif equalsWith(thisLine,'GR')
            nested = nested - 1;
            if nested >= 0
                cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
            else
                % end of block without a 'N' = newpath command
                % we don't know what it is, but we take it as a whole
                operation = 3;
                blockGood = true;
                cbContentLinesIdx = 1;
                cbContentLinesFullIdx = 1;
                [cbNodeCount,cbAdjMat,cbId2idxMap,cbIdx2idArray,cbNewBlock] = getBlockData(blockMap,cbPrefix);
            end
        elseif endsWith(thisLine,'setlinecap')
            hasLineCap = true;
            cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
        elseif endsWith(thisLine,'LJ')
            if hasLineCap
                cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
            else
                % add '1 linecap' if no linecap is specified
                cbPrefix = sprintf('%s%s\n%s\n',cbPrefix,'1 setlinecap',thisLine);
            end
        else
            cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
        end
    elseif operation == 2 % analyze block content
        if startsWith(thisLine,'%AXGBegin')
            % this could be the beginning of a raw bitmap data block -> just take it
            insideAxg = true;
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,true);
        elseif startsWith(thisLine,'%AXGEnd')
            insideAxg = false;
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,true);
        elseif insideAxg
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,true);
        elseif endsWith(thisLine,'re')
            if removeBoxes
                blockGood = false;
            else
                [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,true);
            end
        elseif equalsWith(thisLine,'clip')
            blockMap.remove(cbPrefix);
            cbPrefix = sprintf('%sN\n%s\n%s\n', cbPrefix, strjoin(fileContent(cbContentLinesFull(1:cbContentLinesFullIdx-1))), thisLine);
            cbContentLinesIdx = 1;
            cbContentLinesFullIdx = 1;
            [cbNodeCount,cbAdjMat,cbId2idxMap,cbIdx2idArray,cbNewBlock] = getBlockData(blockMap,cbPrefix);
        elseif endsWith(thisLine,'M')
            lastMoveLine = thisLine;
            lineIdx = lineIdx + 1;
            nextline = cell2mat(fileContent(lineIdx)); % ASSUMPTION: there is an L directly after an M
            lastLineLine = nextline;
            moveId = thisLine(1:end-1);
            lineId = nextline(1:end-1);
            [cbAdjMat,cbIdx2idArray,cbNodeCount] = addConnection(cbAdjMat,cbId2idxMap,cbIdx2idArray,cbNodeCount,moveId,lineId);
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx-1,false);
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,false);
        elseif equalsWith(thisLine,'cp')
            moveId = lastLineLine(1:end-1);
            lineId = lastMoveLine(1:end-1);
            [cbAdjMat,cbIdx2idArray,cbNodeCount] = addConnection(cbAdjMat,cbId2idxMap,cbIdx2idArray,cbNodeCount,moveId,lineId);
            lastLineLine = lastMoveLine;
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,false);
        elseif endsWith(thisLine,'L')
            moveId = lastLineLine(1:end-1);
            lineId = thisLine(1:end-1);
            [cbAdjMat,cbIdx2idArray,cbNodeCount] = addConnection(cbAdjMat,cbId2idxMap,cbIdx2idArray,cbNodeCount,moveId,lineId);
            lastLineLine = thisLine;
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,false);
        elseif equalsWith(thisLine,'f')
            % special handling for filled areas
            [~,cbContentLinesFull,~,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,false);
            cbContentLines = cbContentLinesFull;
            cbContentLinesIdx = cbContentLinesFullIdx;
            % remove all connections:
            cbNodeCount = 0;
        elseif equalsWith(thisLine,'GS')
            nested = nested + 1;
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,true);
        elseif equalsWith(thisLine,'GR')
            % end of block content
            nested = nested - 1;
            if nested >= 0
                [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,true);
            else
                operation = 3; % end of block content
            end
        else
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,true);
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

function r = startsWith(string1, pattern)
    l = length(pattern);
    if length(string1) < l
        r = false;
    else
        r = strcmp(string1(1:l),pattern);
    end
end

function r = endsWith(string1, pattern)
    l = length(pattern);
    if length(string1) < l
        r = false;
    else
        r = strcmp(string1(end-l+1:end),pattern);
    end
end

function r = equalsWith(string1, pattern)
    r = strcmp(string1,pattern);
end

function [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,both)
    if cbContentLinesFullIdx > length(cbContentLinesFull)
        cbContentLinesFull = [cbContentLinesFull -ones(1,100)];
    end
    cbContentLinesFull(cbContentLinesFullIdx) = lineIdx;
    cbContentLinesFullIdx = cbContentLinesFullIdx + 1;

    if both
        if cbContentLinesIdx > length(cbContentLines)
            cbContentLines = [cbContentLines -ones(1,100)];
        end
        cbContentLines(cbContentLinesIdx) = lineIdx;
        cbContentLinesIdx = cbContentLinesIdx + 1;
    end
end

function setBlockData(blockMap,blockId,nodeCount,adjMat,id2idxMap,idx2idArray,contentLines)
    if ~blockMap.isKey(blockId)
        return; % a block without nodes. probably without an 'N' statement
    end
    theblock = blockMap(blockId);
    theblock('nodeCount') = nodeCount;
    theblock('adjMat') = adjMat;
    theblock('id2idxMap') = id2idxMap;
    theblock('idx2idArray') = idx2idArray;

    oldContentLines = theblock('contentLines');
    theblock('contentLines') = [oldContentLines(1:end-1) contentLines]; %#ok<NASGU>
end

function [nodeCount,adjMat,id2idxMap,idx2idArray,newBlock] = getBlockData(blockMap,blockId)
    if blockMap.isKey(blockId)
        newBlock = false;
        theblock = blockMap(blockId);
        nodeCount = theblock('nodeCount');
        adjMat = theblock('adjMat');
        id2idxMap = theblock('id2idxMap');
        idx2idArray = theblock('idx2idArray');
    else
        newBlock = true;
        nodeCount = 0;
        adjMat = false(100);
        id2idxMap = containers.Map('KeyType','char','ValueType','uint32');
        idx2idArray = cell(1,100);
        
        blockMap(blockId) = containers.Map(...
            {'nodeCount','adjMat','id2idxMap','idx2idArray','contentLines'},...
            {nodeCount,adjMat,id2idxMap,idx2idArray,[]}); %#ok<NASGU>
    end
end

function [index,idx2idArray,nodeCount] = getNodeIndex(id2idxMap, idx2idArray, nodeCount, nodeId)
    if id2idxMap.isKey(nodeId)
        index = id2idxMap(nodeId);
    else
        nodeCount = nodeCount + 1;
        index = nodeCount;
        id2idxMap(nodeId) = index; %#ok<NASGU>

        % other direction index -> id:
        if index > length(idx2idArray)
            idx2idArray = [idx2idArray cell(1,100)];
        end
        idx2idArray{index} = nodeId;
    end
end

function [adjMat,idx2idArray,nodeCount] = addConnection(adjMat, id2idxMap, idx2idArray, nodeCount, nodeId1, nodeId2)
    if strcmp(nodeId1, nodeId2)
        return; % ignore zero length lines
    end

    [idx1,idx2idArray,nodeCount] = getNodeIndex(id2idxMap,idx2idArray,nodeCount,nodeId1);
    [idx2,idx2idArray,nodeCount] = getNodeIndex(id2idxMap,idx2idArray,nodeCount,nodeId2);

    adjSize = size(adjMat,1);
    if nodeCount > adjSize
        % resize adjacency matrix
        adjMat = [adjMat false(adjSize, 100)];
        adjMat = [adjMat ; false(100, adjSize+100)];
    end

    adjMat(idx1,idx2) = true;
    adjMat(idx2,idx1) = true;
end

function writeBlocks(blockList, blockMap, fileId, fileContent)
    for ii = 1:length(blockList)
        blockId = blockList(ii).prefix;
        fprintf(fileId, 'GS\n%s', blockId);
        
        theblock = blockMap(blockId);
        nodeCount = theblock('nodeCount');
        idx2idArray = theblock('idx2idArray');
        contentLines = theblock('contentLines');

        am = theblock('adjMat');
        am = am(1:nodeCount,1:nodeCount);
        connCount = sum(am,1);
        total = sum(connCount,2);

        if total == 0
            if ~isempty(contentLines)
                if isempty(regexp(blockId, sprintf('clip\n$'), 'once')) % prefix does not end with clip
                    fprintf(fileId, 'N\n');
                end

                fprintf(fileId, '%s\n', strjoin(fileContent(contentLines),'\n'));
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
                            fprintf(fileId, '%sM\n', cell2mat(idx2idArray(node)));
                            first = false;
                            firstNode = node;
                        end
                        am(node,nni) = false;
                        am(nni,node) = false;
                        if nni == firstNode
                            % closed path (polygon) -> use a 'closepath' command instead of a line
                            fprintf(fileId, 'cp\n');
                        else
                            fprintf(fileId, '%sL\n', cell2mat(idx2idArray(nni)));
                        end
                        node = nni;
                        search = true;
                        break;
                    end
                end
            end 

            fprintf(fileId, '%s\n', strjoin(fileContent(contentLines),'\n'));
        end

        fprintf(fileId, 'GR\n');
    end
end

