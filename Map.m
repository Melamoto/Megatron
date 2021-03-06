%{
    Map and target are given as co-ordinates [x, y].
    Position must be set but can be changed throughout.
    Calls to dijkstraRoute create chain of route to desired target.
%}
classdef Map < handle
    properties
        vertices
        polygonX
        polygonY
        walls
        dijnext
        dijdist
    end
    methods
        function map = Map(map_in, target, robot_radius)
            % store map as list of vertices [x1, y1; x2, y2] and in format for "inpolygon"
            % call later [x1; x2] [y1; y2]
            % Polygons must have the first point as the last point to close the loop
            map.vertices = Map.shrinkMap(map_in, robot_radius);
            map.polygonX = cat(1,map.vertices(:,1), map.vertices(1,1));
            map.polygonY = cat(1,map.vertices(:,2), map.vertices(1,2));
            
            % error if target outside shrunken walls
            if ~inpolygon(target(1), target(2), map.polygonX, map.polygonY)
                error('Target is outside or too close to walls!');
            end
            
            % create list of walls in format [x0, y0, x1, y2], one line per
            % row of array
            map.walls = Map.findWalls(map.vertices);
            
            % add target to vertices and solve for valid distances (including walls)
            map.vertices = [target; map.vertices];
            N = size(map.vertices,1);
            dist = zeros(N,N);
            for a = 1:N
                dist(a, a+1:N) = map.findValidDistances(map.vertices(a,:), map.vertices(a+1:N,:));
                dist(a+1:N, a) = dist(a, a+1:N); % (symetrical matrix)
            end
            
            % get dijikstra chain between map nodes
            [map.dijnext, map.dijdist] = Map.dijkstraChain(dist, 1);
        end
        
        % Creates array of all valid distances between nodes
        % paths are valid if centre is within shape and it doesn't
        % intersect any walls.
        % Walls themselves are valid paths.
        function dist = findValidDistances(map, vert, vertices)
            N = size(vertices,1);
            dist = ones(1,N) * inf;
            for a = 1:N
                p = [vert, vertices(a,:)];
                mid = (vert + vertices(a,:)) / 2;
                % Inpolygon supports concave polygons
                if inpolygon(mid(1),mid(2),map.polygonX,map.polygonY) && ~Map.intersectsAny(map.walls, p) 
                    dist(a) = sqrt( (p(1) - p(3)) .^2 + (p(2) - p(4)) .^ 2 );
                end
            end
        end
        
        % Creates array of all valid paths between nodes
        % paths are valid if centre is within shape and it doesn't
        % intersect any walls.
        % Walls themselves are valid paths.
        function paths = findValidPaths(map, vertices)
            N = size(vertices,1);
            paths = [];
            for a = 1:N
                for b = a+1:N
                    p = [vertices(b,:), vertices(a,:)];
                    mid = (vertices(b,:) + vertices(a,:)) / 2;
                    % Inpolygon supports concave polygons
                    if inpolygon(mid(1),mid(2),map.polygonX,map.polygonY) && ~Map.intersectsAny(map.walls, p) 
                        paths(end+1,:) = p;
                    end
                end
            end
        end
        
        % Find bearing towards target (staying inside map). Empty array if
        % at target or no route found.
        function [x, y, bearing, distance] = findBearing( map, position, prevX, prevY )
            if ~inpolygon(position(1), position(2), map.polygonX, map.polygonY)
                if ~isequal(position, map.vertices(1,:))
                    x = prevX - position(1);
                    y = prevY - position(2);
                    bearing = atan2( y, x);
                    distance = norm([x, y]);
                else
                    bearing = [];
                    distance = 0;
                end
            else
                pdist = map.findValidDistances(position, map.vertices);
                [~, i] = min( map.dijdist + pdist );
                if ~isequal(position, map.vertices(1,:))
                    x = map.vertices(i,1) - position(1);
                    y = map.vertices(i,2) - position(2);
                    bearing = atan2( y, x);
                    distance = norm([x, y]);
                else
                    bearing = [];
                    distance = 0;
                end
            end
        end
        
        function plot( map, position )
            clf
            hold on
            % plot valid routes
            paths = map.findValidPaths([map.vertices; position]);
            for i = 1:size(paths,1)
                plot( paths(i,[1 3]), paths(i,[2 4]), 'b' );
            end
            % plot planned route
            pdist = map.findValidDistances(position, map.vertices);
            [~, i] = min( map.dijdist + pdist );
            last = position;
            while i ~= -1
                plot( [last(1), map.vertices(i,1)], [last(2), map.vertices(i,2)], 'r' );
                last = map.vertices(i,:);
                i = map.dijnext(i);
            end
            % target and position
            scatter(map.vertices(1,1), map.vertices(1,2), 'x', 'r')
            scatter(position(1), position(2), 'o', 'r')
        end
    end
    methods(Static)        
        % returns true if segments B interesects A or they overlap
        % start or end points can be shared, but line cannot cross anothers
        % start or end point
        % lines are defined by array [x0, y0, x1, y1]
        function bool = intersects(A, B)
            denom = Map.cross(A(3:4) - A(1:2), B(3:4) - B(1:2));
            enum = Map.cross(B(1:2) - A(1:2), A(3:4) - A(1:2));
            if denom == 0 
                if enum == 0
                    % colinear (return true if overlapping)
                    bool = Map.onSegment(A(1:2),B) || Map.onSegment(A(3:4), B) ...
                        || Map.onSegment(B(1:2),A) || Map.onSegment(B(3:4), A);
                else
                    % parallel
                    bool = false;
                end
            else
                t = Map.cross(B(1:2) - A(1:2), B(3:4) - B(1:2)) / denom;
                u = enum / denom;
                % fudge for detecting doubles equal to zero or one
                tol = 0.0001;
                tolU = abs(u)<tol || abs(u-1) < tol;
                tolT = abs(t)<tol || abs(t-1)<tol;
                if tolT && ~tolU
                    bool = 0 <= u && u <= 1;
                elseif ~tolT && tolU
                    bool = 0 <= t && t <= 1;
                elseif tolT && tolU
                    bool = false;
                else
                    bool = (0 < t && t < 1 && 0 < u && u < 1);
                end
            end
        end
        
        % returns true if segments B interesects any of A 
        % start or end points can be shared, but line cannot cross anothers
        % start or end point
        % returns true if any colinear
        % lines are defined by array [x0, y0, x1, y1]
        function bool = intersectsAny(A, b)
            for i = 1:size(A,1)
                if Map.intersects(A(i,:), b)
                    bool = true;
                    return
                end
            end
            bool = false;
        end
        
        % return point of intersection (if any) of line P->P+r and Q->Q+s
        % used only for shrinking the map (hence always intersection)
        % NB if lines are colinear will not return a value!
        function point = intersection(P, r, Q, s)
            denom = Map.cross(r, s);
            if denom == 0 
                % if enum = 0 then colinear, else parallel
                point = [];
            else
                t = Map.cross( Q - P, s ) / denom;
                point = P + t * r;
%                 u = Map.cross(Q - P, r) / denom;
%                 if 0 <= t && t <= 1 && 0 <= u && u <= 1
%                     % intersection
%                     point = P + t * r;
%                 else
%                     % no intersection (but skew)
%                     point = [];
%                 end
            end
        end
        
        % two dimensional cross product
        function prod = cross(A,B)
            prod = A(1) * B(2) - A(2) * B(1);
        end
        
        % create list of walls in format [x0, y0, x1, y2], one line per
        % row of array
        function walls = findWalls(vertices)
            walls = zeros(length(vertices),4);
            vertices(end+1,:) = vertices(1,:);
            for i =1:size(walls,1)
                walls(i,:) = [vertices(i,:) vertices(i+1,:)] ;
            end
        end
        
        % Returns vertices formed by shrinking existing shape by [quant].
        % The map is shrunk such that the new walls are [quant] inwards
        % from the old walls, in the direction normal to the old wall.
        function newvert = shrinkMap( vert, quant )
            polygonX = cat(1,vert(:,1), vert(1,1));
            polygonY = cat(1,vert(:,2), vert(1,2));
            newvert = zeros(size(vert));
            n = length(vert);
            for i = 2:length(vert)-1
                a = vert(i,:);
                b = vert(i-1,:);
                c = vert(i+1,:);
                ab = [b(1) - a(1), b(2) - a(2)];
                ac = [c(1) - a(1), c(2) - a(2)];
                uab = ab/norm(ab);
                uac = ac/norm(ac);
                abc = uab+uac;
                uabc = abc/norm(abc);
                newv = vert(i,:) + uabc;
                if ~inpolygon(newv(1), newv(2), polygonX, polygonY)
                    uabc = -uabc;
                    newv = vert(i,:) + uabc;
                    if ~inpolygon(newv(1), newv(2), polygonX, polygonY)
                        error('Bad bubbling1');
                    end
                end
                newvert(i,:) = vert(i,:) + quant*uabc;
            end
            % v(1)
            ab = [vert(2,1) - vert(1,1), vert(2,2) - vert(1,2)];
            ac = [vert(n,1) - vert(1,1), vert(n,2) - vert(1,2)];
            uab = ab/norm(ab);
            uac = ac/norm(ac);
            abc = uab+uac;
            uabc = abc/norm(abc);
            newv = vert(1,:) + uabc;
            if ~inpolygon(newv(1), newv(2), polygonX, polygonY)
                uabc = -uabc;
                newv = vert(1,:) + uabc;
                if ~inpolygon(newv(1), newv(2), polygonX, polygonY)
                    error('Bad bubbling2');
                end
            end
            newvert(1,:) = vert(1,:) + quant*uabc;
            % v(n)
            ab = [vert(1,1) - vert(n,1), vert(1,2) - vert(n,2)];
            ac = [vert(n-1,1) - vert(n,1), vert(n-1,2) - vert(n,2)];
            uab = ab/norm(ab);
            uac = ac/norm(ac);
            abc = uab+uac;
            uabc = abc/norm(abc);
            newv = vert(n,:) + uabc;
            if ~inpolygon(newv(1), newv(2), polygonX, polygonY)
                uabc = -uabc;
                newv = vert(n,:) + uabc;
                if ~inpolygon(newv(1), newv(2), polygonX, polygonY)
                    error('Bad bubbling3');
                end
            end
            newvert(n,:) = vert(n,:) + quant*uabc;
            %last_vec = vert(1,:) - vert(end,:);
            %last_point = vert(end,:) + Map.normal(last_vec) * quant;
            %vert(end+1,:) = vert(1,:); % add final value to end for fudged looping
            %for v = 1:length(vert)-1
            %    vec = vert(v+1,:) - vert(v,:);
            %    point = vert(v,:) + Map.normal(vec) * quant;
            %    newvert(v,:) = Map.intersection(last_point, last_vec, point, vec);
            %    last_vec = vec;
            %    last_point = point;
            %end
        end
        
        % produces the right hand unit normal to a line.
        function normvec = normal(A)
            normvec = (A * [0,-1;1,0]) / norm(A);
        end
        
        % gives the position of point p[x,y] relative to vector line
        % [x,y,x,y]. 0 means p is on the line, +1 it is to the right, -1 it
        % is to the left (looking from first to second point on the line).
        function pos = positionRelativeTo(p, line)
            pos = sign((line(1)-line(3)) * (p(2)-line(4)) - (line(2)-line(4)) * (p(1)-line(2)));
        end
        
        % returns true only if point p[x, y] is on the line l[x,y,x,y] exluding
        % start and end points of the line.
        function bool = onSegment(p, l)
            bool = p(1) < max(l(1), l(3)) && p(1) > min(l(1), l(3)) && p(2) < max(l(2), l(4)) && p(2) > min(l(2), l(4));
        end
        
        % This function calculates the shortest path from each given location in the
        % adjacency matrix A to the target node, using Dijkstra's Algorithm for graph
        % searching/traversal
        % dist(i) is the distance from the ith node to the target
        % next(i) is the next node in the shortest path from the ith node to the target
        function [next, dist] = dijkstraChain(A,target)
            for i = 1:length(A)
                dist(i) = inf(1,1);
                next(i) = -1;
            end

            dist(target) = 0;

            for i = 1 :length(A)
                status(i) = 0;
            end
            checked = 0;

            while (length(A) > checked)

                minElem = inf;
                for j = 1:length(A)
                    if (status(j) ~= 1 && dist(j) < minElem)
                        minElem = dist(j);
                        mindex = j;
                    end
                end

                for j = 1:length(A)
                    if (A(mindex,j) > 0 && j ~= mindex)
                        alt = dist(mindex) + A(mindex,j);

                        if alt < dist(j)
                            dist(j) = alt;
                            next(j) = mindex;
                        end
                    end
                end

                status(mindex) = 1;
                checked = checked + 1;
            end
        end
    end
end
