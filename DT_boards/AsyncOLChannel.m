classdef AsyncOLChannel < matlabshared.asyncio.internal.Channel
    %AsyncOLChannel Class for Asynchronous Open layers Channels
    %
    %    This undocumented class may be removed in a future release.
    
    % Copyright 2015-2016 Data Translation, Inc.
    
    properties
        DeviceName = ''; % Optional (to be used for lookup)
    end
    
    %% Lifetime
    methods
        function obj = AsyncOLChannel(channelOptions, streamLimits, pluginInfo)
            % Define a plugin directory if one isn't provided
            if nargin < 3
                pluginInfo.converterPath = fullfile(toolboxdir('daq'), 'daqsdk', 'bin', computer('arch'),'daqmlconverter');
                pluginInfo.devicePath = fullfile(toolboxdir('daq'), 'daqsdk', 'bin', computer('arch'),'daqasyncio');
            end
 
            obj@matlabshared.asyncio.internal.Channel(pluginInfo.devicePath, ...
                               pluginInfo.converterPath,...
                               'Options', channelOptions,...
                               'StreamLimits', streamLimits);
        end
    end
    
   
    methods (Access = {?daq.dt.internal.ChannelGroupOL})
        function postDataWritten(obj)
            try            
                remainderIn = obj.InputStream.DataAvailable;
                if ~any(isinf(remainderIn))
                        notify(obj.InputStream, 'DataWritten', ...
                            matlabshared.asyncio.internal.DataEventInfo(remainderIn) );
                end
            catch e
                switch e.identifier
                    case 'asyncio:InputStream:notSupported'
                    otherwise
                        throw(e);
                end
            end            
        end
        
        function postDataRead(obj)
            try            
                remainderOut = obj.OutputStream.SpaceAvailable;
                if ~any(isinf(remainderOut))
                        notify(obj.OutputStream, 'DataRead', ...
                            matlabshared.asyncio.internal.DataEventInfo(remainderOut) );
                end
            catch e
                switch e.identifier
                    case 'asyncio:OutputStream:notSupported'
                    otherwise
                        throw(e);
                end
            end            
            
        end
    end
end

