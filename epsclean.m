function epsclean( file, varargin )
% EPSCLEAN Cleans up a MATLAB exported .eps file.
%
%   EPSCLEAN(F,...) cleans the .eps file F without removing box elements and optional parameters.
%   EPSCLEAN(F,O,...) cleans the .eps file F, writes the result to file O and optional parameters.
%   EPSCLEAN(F,O,R,G) (deprecated) cleans the .eps file F, writes the result to file O and optionally removes box
%                     elements if R = true. Optionally it groups elements 'softly' if G = true.
%
%   Optional parameters (key/value pairs) - see examples below
%   - outFile      ... Defines the output file for the result. Default is overwriting the input file.
%   - groupSoft    ... Groups elements only if they occur sequentially. Can help with Z-order problems. Defaults to false.
%   - combineAreas ... Combines filled polygons to larger ones. Can help with artifacts. Defaults to false.
%   - removeBoxes  ... Removes box (rectangle) elements. Defaults to false.
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
%   It also removes paths with 're' (rectangle) elements when supplying the parameter 'removeBoxes' with true.
%   In case the 'groupSoft' parameter is true it does not group elements according to their properties over the whole
%   document. It will rather group them only if the same elements occur sequentially, but not if they are interrupted by
%   elements with different properties. This will result in more fragmentation, but the Z-order will be kept intact. Use
%   this (set to true) if you have trouble with the Z-order.
%   If the 'combineAreas' parameter is true it combines filled polygons with the same properties to larger polygons of
%   the same type. It reduces clutter and white-line artifacts. The downside is that it's about 10 times slower.
%
%   Example 1
%   ---------
%       z = peaks;
%       contourf(z);
%       print(gcf,'-depsc','-painters','out.eps');
%       epsclean('out.eps'); % cleans and overwrites the input file
%       epsclean('out.eps','clean.eps'); % leaves the input file intact
%       epsclean('out.eps','clean.eps','combineAreas',true); % result in 'clean.eps', combines polygon areas
%       epsclean('out.eps','groupSoft',true,'combineAreas',true); % overwrites file, combines polygons, Z-order preserved
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
%   2017-04-18 (YYYY-MM-DD)
%   - Major performance increase for creating the adjacency matrix (for creating continous polylines)
%   - A lot of other performance enhancements
%   2017-05-28 (YYYY-MM-DD)
%   - Added the possibility to merge adjacent polygons to avoid artifacts
%     o See https://github.com/Conclusio/matlab-epsclean/issues/9
%   - Changed argument style
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

% default values:
removeBoxes = false;
groupSoft = false;
combineAreas = false;
outfile = file;

fromIndex = 1;
% check for old argument style (backward compatibility)
if nargin >= 2 && ischar(varargin{1}) && ~strcmpi(varargin{1},'removeBoxes') && ~strcmpi(varargin{1},'groupSoft') && ~strcmpi(varargin{1},'combineAreas')
    fromIndex = 2;
    outfile = varargin{1};
    if nargin >= 3
        if islogical(varargin{2})
            fromIndex = 3;
            removeBoxes = varargin{2};
            if nargin >= 4 && islogical(varargin{3})
                fromIndex = 4;
                groupSoft = varargin{3};
            end
        end
    end
end

p = inputParser;
p.CaseSensitive = false;
p.KeepUnmatched = false;

addParameter(p,'outFile',outfile,@ischar);
addParameter(p,'removeBoxes',removeBoxes,@islogical);
addParameter(p,'groupSoft',groupSoft,@islogical);
addParameter(p,'combineAreas',combineAreas,@islogical);

parse(p,varargin{fromIndex:end});
outfile = p.Results.outFile;
removeBoxes = p.Results.removeBoxes;
groupSoft = p.Results.groupSoft;
combineAreas = p.Results.combineAreas;

keepInput = true;
if strcmp(file, outfile)
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
isDashMode = false;
blockList = [];

nested = 0;
lastMLine = [];
lastLLine = [];
blockMap = containers.Map(); % key=blockPrefix -> MAP with connection information and content for blocks

% current block (cb) data:
cbPrefix = '';
cbContentLines = -ones(1,100);
cbContentLinesFull = -ones(1,100);
cbContentLinesIdx = 1;
cbContentLinesFullIdx = 1;
cbConn = {};
cbIsFill = false;

% load whole file into memory:
fileContent = textscan(fid1,'%s','delimiter','\n','whitespace','');
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

            [cbNewBlock,oldConn,oldConnFill] = getBlockData(blockMap,cbPrefix);
            removeLastContentLine = false;
            if cbIsFill
                if combineAreas
                    oldConnFill = [oldConnFill cbConn]; %#ok<AGROW>
                else
                    removeLastContentLine = true;
                end
            else
                oldConn = [oldConn cbConn]; %#ok<AGROW>
            end
            setBlockData(blockMap,cbPrefix,cbContentLines(1:cbContentLinesIdx-1),oldConn,oldConnFill,removeLastContentLine);
            if cbNewBlock
                % new block
                block = struct('prefix', cbPrefix);
                blockList = [blockList block]; %#ok<AGROW>
            end
        end
        operation = 0;
        previousBlockPrefix = cbPrefix;
        cbPrefix = '';
    end


    if operation == 0 % waiting for blocks
        if equalsWith(thisLine,'GS')
            % start of a block
            operation = 1;
            hasLineCap = false;
            isDashMode = false;
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
            lastMLine = [];
            cbConn = {};
            cbIsFill = false;
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
                cbConn = {};
                cbIsFill = false;
            end
        elseif endsWith(thisLine,'setdash')
            isDashMode = true;
            cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
        elseif endsWith(thisLine,'setlinecap')
            hasLineCap = true;
            cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
        elseif endsWith(thisLine,'LJ')
            if hasLineCap
                cbPrefix = sprintf('%s%s\n',cbPrefix, thisLine);
            elseif ~isDashMode
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
            cbPrefix = sprintf('%sN\n%s\n%s\n', cbPrefix, strjoin(fileContent(cbContentLinesFull(1:cbContentLinesFullIdx-1))), thisLine);
            cbContentLinesIdx = 1;
            cbContentLinesFullIdx = 1;
            cbConn = {};
            cbIsFill = false;
        elseif endsWith(thisLine,'M')
            lastMLine = thisLine;
            lineIdx = lineIdx + 1;
            nextline = cell2mat(fileContent(lineIdx)); % ASSUMPTION: there is an L directly after an M
            lastLLine = nextline;
            
            moveId = thisLine(1:end-1);
            lineId = nextline(1:end-1);
            
            [cbConn] = addConnection(moveId,lineId,cbConn);
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx-1,false);
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,false);
        elseif equalsWith(thisLine,'cp')
            moveId = lastLLine(1:end-1);
            lineId = lastMLine(1:end-1);
            lastLLine = lastMLine;

            [cbConn] = addConnection(moveId,lineId,cbConn);
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,false);
        elseif endsWith(thisLine,'L')
            moveId = lastLLine(1:end-1);
            lineId = thisLine(1:end-1);
            lastLLine = thisLine;

            [cbConn] = addConnection(moveId,lineId,cbConn);
            [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,false);
        elseif equalsWith(thisLine,'S')
            % ignore stroke command
        elseif equalsWith(thisLine,'f')
            % special handling for filled areas
            cbIsFill = true;
            if combineAreas
                lastLine = cell2mat(fileContent(lineIdx-1));
                if ~equalsWith(lastLine, 'cp')
                    [cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,true);
                end
            else
                [~,cbContentLinesFull,~,cbContentLinesFullIdx] = addContent(cbContentLines,cbContentLinesFull,cbContentLinesIdx,cbContentLinesFullIdx,lineIdx,false);
                cbContentLines = cbContentLinesFull;
                cbContentLinesIdx = cbContentLinesFullIdx;
                % remove all connections:
                cbConn = {};
            end
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
    movefile(outfile, file, 'f');
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

function setBlockData(blockMap,blockId,contentLines,conn,connFill,removeLastContentLine)
    if ~blockMap.isKey(blockId)
        return; % a block without nodes. shouldn't happen.
    end
    theblock = blockMap(blockId);
    if removeLastContentLine
        theblock.contentLines = [theblock.contentLines(1:end-1) contentLines];
    else
        theblock.contentLines = [theblock.contentLines contentLines];
    end    
    theblock.conn = conn;
    theblock.connFill = connFill;
    blockMap(blockId) = theblock; %#ok<NASGU>
end

function [newBlock,conn,connFill] = getBlockData(blockMap,blockId)
    if blockMap.isKey(blockId)
        newBlock = false;
        theblock = blockMap(blockId);
        conn = theblock.conn;
        connFill = theblock.connFill;
    else
        newBlock = true;
        conn = {};
        connFill = {};
        
        s = struct();
        s.contentLines = [];
        s.conn = conn;
        s.connFill = connFill;
        
        blockMap(blockId) = s; %#ok<NASGU>
    end
end

function [conn] = addConnection(nodeId1, nodeId2, conn)
    conn{1,end+1} = nodeId1; % from
    conn{2,end}   = nodeId2; % to
end

function [am,idx2idArray,edge2idxMat,connCount,total] = buildAdjacencyMatrix(conn)
    if isempty(conn)
        am = [];
        idx2idArray = [];
        edge2idxMat = [];
    else
        from = conn(1,:); % from nodes
        to = conn(2,:); % to nodes
        [idx2idArray,~,ic] = unique([from to]);

        fromIdx = ic(1:length(from));
        toIdx = ic(length(from)+1:end);
        edge2idxMat = [fromIdx' ; toIdx'];

        nodeCount = max(ic);
        am = false(nodeCount); % adjacency matrix

        idx1 = sub2ind(size(am),fromIdx,toIdx);
        idx2 = sub2ind(size(am),toIdx,fromIdx);
        idxD = sub2ind(size(am),1:nodeCount,1:nodeCount);
        am(idx1) = true;
        am(idx2) = true;
        am(idxD) = false; % diagonal
    end

    connCount = sum(am,1);
    total = sum(connCount,2);
end

function printLines(fileId,am,idx2idArray,connCount,total)
    if total == 0
        return;
    end

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
    
    fprintf(fileId, 'S\n');
end

function printFills(fileId,am,idx2idArray,total,edge2idxMat)
    if total == 0
        return;
    end
    
    edgepolymat = zeros(size(am));
    edgeusemat = zeros(size(am));
    
    nodeCount = size(idx2idArray,2);
    edgeCount = size(edge2idxMat,2);
    polyIdxs = zeros(1,edgeCount);

    % determine connections -> polygon:
    polyIdx = 0;
    edge = 1;
    while true
        if edge <= edgeCount
            startIdx = edge2idxMat(1,edge);
        else
            break;
        end
        polyIdx = polyIdx + 1;
        
        while edge <= size(edge2idxMat,2)
            tidx = edge2idxMat(2,edge);
            polyIdxs(edge) = polyIdx;
            
            edge = edge + 1;
            if startIdx == tidx
                break; % polygon finished
            end
        end
    end
    
    % check whether or not a polygon has the same edge defined twice
    polyCount = polyIdx;
    selfEdges = false(1,polyCount);
    for ii = 1:polyCount
        selfEdges(ii) = hasEdgeWithItself(edge2idxMat,polyIdxs,ii);
    end    
    
    % check if there are initial self edges and if so, just pretend we have been visiting those polygons already:
    k=find(selfEdges);
    for kk = k
        ii = edge2idxMat(:,polyIdxs == kk);
        idxs1 = sub2ind(size(edgeusemat), ii(1,:), ii(2,:));
        idxs2 = sub2ind(size(edgeusemat), ii(2,:), ii(1,:));
        idxs = [idxs1 idxs2];
        edgeusemat(idxs) = edgeusemat(idxs) + 1;
        edgeusemat(idxs) = edgeusemat(idxs) + 1;
        edgepolymat(idxs) = kk;
        edgepolymat(idxs) = kk;
    end
    
    
    polyIdx = 0;
    edge = 1;
    initialEdgeCount = size(edge2idxMat,2);
    while true
        if edge <= initialEdgeCount
            startIdx = edge2idxMat(1,edge);
        else
            break;
        end
        polyIdx = polyIdx + 1;
        
        if selfEdges(polyIdx)
            % polygon has edge with itself, don't try to merge and skip polygon instead
            edge = edge + find(edge2idxMat(2,edge:end) == tidx,1);
        else
            handledPolyMap = containers.Map('KeyType','double','ValueType','any');

            while edge <= initialEdgeCount
                fidx = edge2idxMat(1,edge);
                tidx = edge2idxMat(2,edge);
                                
                removeEdge = false;
                nPolyIdx = edgepolymat(fidx,tidx);
                if nPolyIdx > 0
                    if ~selfEdges(nPolyIdx)
                        if handledPolyMap.isKey(nPolyIdx)
                            % leave the edge intact, except if it's connected to the shared edge
                            val = handledPolyMap(nPolyIdx);
                            f = val(1);
                            t = val(2);
                            connected = true;
                            if f == fidx
                                f = tidx;
                            elseif f == tidx
                                f = fidx;
                            elseif t == fidx
                                t = tidx;
                            elseif t == tidx
                                t = fidx;
                            else
                                connected = false;
                            end
                            if connected
                                fusage = sum(edgeusemat(fidx,:) > 0);
                                tusage = sum(edgeusemat(tidx,:) > 0);
                                removeEdge = (fusage == 1 || tusage == 1);
                                if removeEdge
                                    handledPolyMap(nPolyIdx) = [f t];
                                end
                            end
                        else
                            % remove the first common shared edge
                            handledPolyMap(nPolyIdx) = [fidx tidx];
                            removeEdge = true;
                        end
                    end
                else
                    edgepolymat(fidx,tidx) = polyIdx;
                    edgepolymat(tidx,fidx) = polyIdx;
                end
                
                if removeEdge
                    edgepolymat(fidx,tidx) = 0;
                    edgepolymat(tidx,fidx) = 0;
                    edgeusemat(fidx,tidx) = 0;
                    edgeusemat(tidx,fidx) = 0;
                    polyIdxs(edge) = 0;
                else
                    edgeusemat(fidx,tidx) = edgeusemat(fidx,tidx) + 1;
                    edgeusemat(tidx,fidx) = edgeusemat(tidx,fidx) + 1;
                end
                
                edge = edge + 1;
                if startIdx == tidx
                    break; % polygon finished
                end
            end

            % merge all handled polygons:
            for k = cell2mat(handledPolyMap.keys())
                edgepolymat(edgepolymat == k) = polyIdx;
                polyIdxs(polyIdxs == k) = polyIdx;
            end
            selfEdges(polyIdx) = hasEdgeWithItself(edge2idxMat,polyIdxs,polyIdx);
        end
    end
    
        
    
    connCount = sum(edgeusemat, 1);

    coordinates = zeros(nodeCount,2);
    remainingNodes = find(connCount);
    for c = remainingNodes
        coordinates(c,:) = extractCoords(idx2idArray(c));
    end

    fprintf(fileId, 'N\n');

    [~,sidx] = sort(connCount); % sort by lowest connection count
    for ni = sidx
        firstNode = -1;
        prevNode = -1;
        first = true;
        search = true;
        node = ni;
        unkLeftRight = 0;

        while(search)
            c = edgeusemat(node,:);
            [~,sidx2] = sort(c(c>0),'descend'); % sort by edge-usage (select higher usage first)
            neighbours = find(c);
            neighbours = neighbours(sidx2);
            neighbours(neighbours == prevNode) = []; % don't go backwards
            search = false;
            nidx = 0;
            for nni = neighbours
                nidx = nidx + 1;
                if edgeusemat(node,nni) == 0
                    continue; % edge already visited
                end
                
                if length(neighbours) >= 2
                    if unkLeftRight > 0
                        p = coordinates(prevNode,:);
                        c = coordinates(node,:);
                        n = coordinates(nni,:);
                        
                        valid = true;
                        for nni2 = neighbours
                            if nni2 == nni
                                continue;
                            end
                            
                            a = coordinates(nni2,:);
                            leftRight = isNodeRight(p,c,n,a);

                            if unkLeftRight ~= leftRight
                                valid = false;
                                break;
                            end
                        end
                        
                        if ~valid
                            continue; % other neighbour
                        end
                    elseif edgeusemat(node,nni) == 2 && prevNode ~= -1
                        % a double edge with more than one option -> remember which way we go (ccw or cw)
                        p = coordinates(prevNode,:); % previous node
                        c = coordinates(node,:); % current node
                        n = coordinates(nni,:); % next node
                        a = coordinates(neighbours(1 + ~(nidx-1)),:); % alternative node
                        
                        unkLeftRight = isNodeRight(p,c,n,a);
                    end
                end
                
                if first
                    fprintf(fileId, '%sM\n', cell2mat(idx2idArray(node)));
                    first = false;
                    firstNode = node;
                end
                
                edgeusemat(node,nni) = edgeusemat(node,nni) - 1;
                edgeusemat(nni,node) = edgeusemat(nni,node) - 1;
                if nni == firstNode
                    % closed path (polygon) -> use a 'closepath' command instead of a line
                    fprintf(fileId, 'cp\n');
                else
                    fprintf(fileId, '%sL\n', cell2mat(idx2idArray(nni)));
                end
                prevNode = node;
                node = nni;
                search = true;
                break;
            end
        end
    end
    
    fprintf(fileId, 'f\n');
end

function value = hasEdgeWithItself(id2idxMat,polyIdxs,polyIdx)
    % check if same edge exists twice in polygon
    edgePoly = id2idxMat(:,polyIdxs == polyIdx);
    edgePoly2 = [edgePoly(2,:) ; edgePoly(1,:)];
    [~,~,ic] = unique([edgePoly' ; edgePoly2'],'rows');
    ic = accumarray(ic,1); % count the number of identical elements
    value = any(ic > 1);
end

function leftRight = isNodeRight(p,c,n,a)
    v1 = c - p; v1 = v1 ./ norm(v1);
    v2 = n - c; v2 = v2 ./ norm(v2);
    v3 = a - c; v3 = v3 ./ norm(v3);

    s2 = sign(v2(1) * v1(2) - v2(2) * v1(1));
    side = s2 - sign(v3(1) * v1(2) - v3(2) * v1(1));
    if side == 0
        % both vectors on the same side
        if s2 == 1
            % both vectors left
            right = dot(v1,v2) > dot(v1,v3);
        else
            % both vectors right
            right = dot(v1,v2) < dot(v1,v3);
        end
    else
        right = side < 0;
    end
    
    leftRight = 1;
    if right
        leftRight = 2;
    end
end

function p = extractCoords(nodeId)
    nodeId = cell2mat(nodeId);
    k = strfind(nodeId, ' ');
    x = str2double(nodeId(1:k(1)));
    y = str2double(nodeId(k(1)+1:end));
    p = [x y];
end

function writeBlocks(blockList, blockMap, fileId, fileContent)
    for ii = 1:length(blockList)
        blockId = blockList(ii).prefix;
        fprintf(fileId, 'GS\n%s', blockId);
        
        theblock = blockMap(blockId);
        contentLines = theblock.contentLines;

        % build adjacency matrix from connections:
        [amL,idx2idArrayL,~,connCountL,totalL] = buildAdjacencyMatrix(theblock.conn);
        [amF,idx2idArrayF,edge2idxMatF,~,totalF] = buildAdjacencyMatrix(theblock.connFill);
        
        total = totalL + totalF;

        if total == 0
            if ~isempty(contentLines)
                if isempty(regexp(blockId, sprintf('clip\n$'), 'once')) % prefix does not end with clip
                    fprintf(fileId, 'N\n');
                end

                fprintf(fileId, '%s\n', strjoin(fileContent(contentLines),'\n'));
            end
        else
            printLines(fileId,amL,idx2idArrayL,connCountL,totalL);
            printFills(fileId,amF,idx2idArrayF,totalF,edge2idxMatF);

            if ~isempty(contentLines)
                fprintf(fileId, '%s\n', strjoin(fileContent(contentLines),'\n'));
            end
        end

        fprintf(fileId, 'GR\n');
    end
end

