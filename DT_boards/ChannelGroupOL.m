classdef (Hidden) ChannelGroupOL < daq.internal.BaseClass
    %ChannelGroupOL Represents the activities associated with a group of OpenLayers channels. 
    % OpenLayers channel groups describe channels belonging to a single
    % subsystem and also associate these channels with an asynchronous I/O
    % channel.
    %
    %    This undocumented class may be removed in a future release.
    
    % Copyright 2015-2016 Data Translation, Inc.
        
    properties
        InitOptions
        
        OpenOptions
        
        InputChannelMap
        
        OutputChannelMap
        
        PluginFolder;
        
        % Asynchronous I/O Channel
        AsynchronousIoChannel = matlabshared.asyncio.internal.Channel.empty();       
        
        % Listeners for AsynchronousIoChannel events
        %  Channel Event: 'Custom' 
        CustomListener = event.listener.empty();     
        
        %  Channel.InputStream Event: DataWritten  
        DataWrittenListener = event.listener.empty();
        
        %  Channel.OutputStream Event: DataRead
        DataReadListener = event.listener.empty();
        
        IsDoneEventReceived
        
        ScansWritten
        DataToOutput
        NotifyWhenScansQueuedBelow
        
    end
    
       
    %% Lifetime: constructor/destructor    
    methods
        function obj = ChannelGroupOL(session, initOptions, streamLimits, pluginFolder)

            % Initialize channel group Properties
            obj.Session = session;
            obj.InitOptions = initOptions;
             
            pluginInfo.pluginFolder = pluginFolder;
            pluginInfo.converterPath = fullfile(toolboxdir('daq'), 'daqsdk', 'bin', computer('arch'),'daqmlconverter');
            pluginInfo.devicePath = fullfile(toolboxdir('daq'), 'daqsdk', 'bin', computer('arch'),'daqasyncio');
            
            obj.PluginFolder = pluginFolder;
            
            mexFileName = fullfile(pluginFolder,'mexOldaApi.mexw64');
            initOptions.NameOfMexFile = mexFileName;
            
            try % Create a AsyncOLChannel

                obj.AsynchronousIoChannel = daq.dt.internal.AsyncOLChannel(...
                    initOptions, ...
                    streamLimits, ...
                    pluginInfo);
                obj.AsynchronousIoChannel.TraceEnabled = false;
            catch e
            
                id = lower(e.identifier);
                fAdjustPath = @(apath) strrep(strcat(apath, '.dll'), '\', '\\');
                
                switch(id)
                    case lower('asyncio:Channel:couldNotLoadConverter')
                        converterPath = fAdjustPath(pluginInfo.converterPath);
                        throw(MException('dt:ol:dtmlconverterNotFound',...
                            sprintf('File not found:%s ', converterPath)));

                    case lower('asyncio:Channel:couldNotLoadDevice')
                        devicePath = fAdjustPath(pluginInfo.devicePath);
                        throw(MException('dt:ol:dtpluginNotFound',...
                            sprintf('File not found:%s ', devicePath)));
                        
                        %obj.localizedError('dt:ol:dtpluginNotFound',...
                         %   devicePath);
                    otherwise
                        
                end
            end
            
            % All ChannelGroups have a custom listener           
            obj.CustomListener = addlistener(...
            obj.AsynchronousIoChannel,...
                'Custom', ...
                @obj.handleCustomEvent);
            
            obj.CustomListener.Recursive = true;

            obj.IsOpen = false;
            
            obj.ErrorOccurred = [];
                           
        end
        
        function delete(obj)
            obj.closeChannel();
            obj.flushChannel();            
               
            delete(obj.DataReadListener);
            delete(obj.DataWrittenListener);
            delete(obj.CustomListener);

            delete(obj.AsynchronousIoChannel);
            obj.AsynchronousIoChannel = [];
        end
    end
    
    %% ChannelGroup: Commands (prepare, release, start, stop)
    methods (Sealed)
        
        function prepare(obj, initOptions,inputChannelMap, outputChannelMap)
            obj.InitOptions = initOptions;
            obj.InputChannelMap = inputChannelMap;
            obj.OutputChannelMap = outputChannelMap;
            
            obj.flushChannel();
        end
        
        function open(obj, openOptions)
            obj.OpenOptions = openOptions;
            obj.openChannel();
        end
        
        function release(obj)
            obj.closeChannel();
        end
        
        function start(obj)
            obj.IsDoneEventReceived = false;
           obj.AsynchronousIoChannel.execute('StartDevice');
        end
        
        function stop(obj)
            
            import daq.dt.internal.OLChannelStopInfo;
                         
           obj.AsynchronousIoChannel.execute('StopDevice');
            
          
            % Wait until the done event happens. This should happen because
            % we explicitly stopped the stream.
          %  while (~obj.IsDoneEventReceived)
           %     pause(1e-3);
           % end
            obj.stopChannel();  % Let listeners know that the device managed by the
            
            % ChannelGroup has stopped.
            errorOccurred = obj.ErrorOccurred;
            groupHandle = obj.InitOptions.ChannelGroupHandle;
            notify(obj,...
                 'Done', ...
                 OLChannelStopInfo(groupHandle, errorOccurred));
             
                        
        end
              
    end
    
    %% Listener creation methods
    methods (Sealed)
        % AsynchronousIoChannel will return a 'DataWritten' event upon an INPUT
        function createDataWrittenListener(obj, dataWrittenEventHandler)
            obj.createDataWrittenListenerHook(dataWrittenEventHandler);
        end
        
        % AsynchronousIoChannel will return a 'DataRead' event upon an OUTPUT 
        function createDataReadListener(obj, dataReadEventHandler)
            obj.createDataReadListenerHook(dataReadEventHandler);
        end
    end      
    
    methods (Access = protected, Sealed)
        function exception = createDroppedSamplesException(obj, numSamplesDropped, typeSamples)
            deviceName = obj.AsynchronousIoChannel.DeviceName;
            additionalMsg = 'Please verify that enough data is being enqueued in the callback for the ''DataRequired'' listener.';
            exception = ...
                MException('dt:ol:samplesDropped', ...
                           'Error occurred during analog %s: Device ''%s'' dropped %d samples.\n%s', ...
                           typeSamples, deviceName, numSamplesDropped, additionalMsg);
        end
        
    end
    
    % State-Accessible Methods
    methods (Access = protected)
        
        function doPrepare(obj, initOptions)
            % Open the channel in order to verify options are ok
            % If options are ok, then stop the channel.
            obj.InitOptions = initOptions;
            obj.flushChannel();
        end
        
        function doRelease(obj)
            obj.closeChannel();
        end
        
        function doStart(obj)
            obj.AsynchronousIoChannel.execute('StartDevice');
        end
        
        function handleStop(obj, error)
            obj.doStop();
            obj.Session.handleStop(error);
        end
                     
    end
    
    %% Asynchronous Channel: Commands (closeChannel, openChannel, stopChannel, flushChannel)
    methods
        function closeChannel(obj)
            % AsynchronousIoChannel does not flush upon close
            if ~isempty(obj.AsynchronousIoChannel)
                obj.AsynchronousIoChannel.close();
                obj.IsOpen = false;
            end
        end
        
        function openChannel(obj)
            
            obj.preOpenHook();
            try 
                obj.AsynchronousIoChannel.open(obj.OpenOptions);
            catch exception
                errorId = exception.identifier;
                errorMsg = exception.message;
                obj.localizedError(errorId, errorMsg);
            end
            obj.IsOpen = true;
        end
        
        function stopChannel(obj)
            % Only flush the Outputstream; 
            % InputStream will be flushed after read or open
            if obj.IsOpen
                obj.preCloseHook();
                obj.closeChannel();
            end
        end
        
        function flushChannel(obj)
            if ~isempty(obj.AsynchronousIoChannel)
                obj.flushHook();
            end
        end
        
    end
    
    %% Protected
    
    % Protected properties
    properties (GetAccess = protected, SetAccess = protected)
        % A map of all the possible states of the ChannelGroup
        StateMap
        
        % Handle to the session object, used to dispatch AsyncIO events.
        Session
    end

    methods (Access = protected)
        
        function preCloseHook(obj) %#ok<MANU>
            % Called prior to device close
        end
        
        function preOpenHook(obj) %#ok<MANU>
            % Called prior to device open
        end
        
        function flushHook(obj) %#ok<MANU>
            % ChannelGroups may choose to flush input/output streams
            % specifically
        end
       
        % Events for the ChannelGroupManager to listen to, as necessary
        function handleCustomEvent(obj, src, event)
            switch event.Type
                case 'StartEvent'
                    % Triggered upon successful channel open
                    % Do Nothing
                case 'ScansGeneratedEvent'
                   if obj.AsynchronousIoChannel.TraceEnabled
                        fprintf('\nhandleCustomEvent.ScansGeneratedEvent = %d\n', event.Data.ScansGenerated);
                   end
                   obj.Session.handleOutputEvent(event.Data.ScansGenerated,obj.OutputChannelMap.session);
                case 'DoneEvent'
                    % Triggered when all samples have been played/recorded
                    obj.IsDoneEventReceived = true;
                    
                    if (~obj.OpenOptions.IsContinuous)
                        obj.stop();
                    end
                    
                case 'OutputSamplesDroppedEvent'
                    numDroppedSamples = event.Data.NumDroppedSamples;
                    typeSamples = 'output';

                    obj.ErrorOccurred = obj.createDroppedSamplesException(numDroppedSamples, typeSamples);
                    obj.stop();                    
                case 'InputSamplesDroppedEvent'
                    % Do nothing in the event of input samples dropped
                    
                otherwise
                    % Do nothing
            end
            
        end
        
        % AsynchronousIoChannel will return a 'DataWritten' event upon an INPUT
        function createDataWrittenListenerHook(obj, dataWrittenEventHandler) %#ok<INUSD>
        end
        
        % AsynchronousIoChannel will return a 'DataRead' event upon an OUTPUT 
        function createDataReadListenerHook(obj, dataReadEventHandler) %#ok<INUSD>
        end    
    end

    %% Overrides
    
    % We do not want to override resetImpl: the ChannelGroupManager shall
    % delete all ChannelGroup instances

    methods (Sealed, Access = protected)
        function resetImpl(obj) %#ok<MANU>
            % Release the subsystem handle associated with the group
             %obj.Session.closeDevicesInSession();
             
            % Release the device handle associated with the group
            
        end
    end        
    
    %% events: protected 
    % (only classes conforming to interface may issue these events)
    
    events %(NotifyAccess = protected)
        Start
        Done
        UnknownEvent
    end
    
    %% Read-Only / Non-Constant 
    
    properties (GetAccess = public, SetAccess = private)
       SampleRate
       BitsPerSample
    end
    
    properties (GetAccess = public, SetAccess = private, Dependent)
        CurrentSample
        TotalSamples
    end  
    
    properties (GetAccess = protected, SetAccess = private)
        State
    end    
    
    %% Private
    
    % Private methods
    methods (Access = private)
                
        function sortedIndices = sortSessionIndicesInDeviceOrder(obj, channelMap) %#ok<INUSL>
            % Device channel indices in _session_ channel order
            deviceIndices = channelMap.device;
            % Session channel indices in _session_ channel order
            sessionIndices = channelMap.session;
            [~, deviceIndexOrder] = sort(deviceIndices);
            
            % Session channel indices in _device_ channel order
            sortedIndices = sessionIndices(deviceIndexOrder);
        end    
    end
    
    %% Accessor methods
    
    methods
        
        function inputChannelMap = get.InputChannelMap(obj)
            % Device data is returned in _device_ channel order. However,
            % session references device channels in the order a user enters
            % them. Device data should be returned in the order entered by
            % the user.
            
            % Device channel indices in _session_ channel order
            deviceIndices = obj.InputChannelMap.device;
            % Session channel indices in _session_ channel order
            channelIndices = obj.InputChannelMap.session;
            
            [~, i] = sort(deviceIndices);
            % Session channel indices in _device_ channel order
            inputChannelMap = channelIndices(i);            
        end
        
        function value = get.TotalSamples(obj)
            if isempty(obj.AsynchronousIoChannel)
                value = 0;
            else
                value = min(obj.SamplesToRead, ...
                            obj.AsynchronousIoChannel.InputStream.DataAvailable);
                value = double(value);
            end
        end
    end
    
    %% Private

    % Flags
    properties (Access = private)
        IsOpen = false;
        ErrorOccurred = [];
    end
        
    properties (Access = private)
        SamplesToRead
    end
   
end

