classdef ECG_Process < handle
    %% ECG_Process - GUI to process ECG to extract heart rate.
    % Consists in three main steps: 
    %   - ECG preprocessing: substraction of a smoothed version of the
    %   signal to remove the offset, and bandpass filtering if needed
    %   - Automated beat detection
    %   - Manual verification in the GUI 
    %
    %   Results and parameters used for the analysis are saved in a .mat
    %   file in the same folder, and with _HeartBeats added to the original
    %   file name.
    %   
    %   NB: loading such file allows to modify the previously saved results
    %
    %   The parameters for each step can be changed through the GUI which
    %   allows to easily adjust them. Beats correction is easy, via simple
    %   clicking.
    %
    %   NB: supported formats are so far normal text files, matlab files, 
    %   .eeg files, Plexon and TDT tanks. +
    %
    %
    % Future implementations/changes:
    %       - better documentation
    %       - create different sets of default parameters for the different
    %       conditions
    %       - implement and refine the algorithm in this version of the
    %       tool
    %       - autoscale ignoring the artefacts segments
    %       - shaded area on the heart rate to show the "abnormal" zone due
    %       to the sliding windows overlaping with the margins of excluded 
    %       segments
    %       - tool showing suspicious ranges to be manually checked
    %       - option to manually validate a few beats to give a good start
    %       to the algorithm if needed
    %       - optimize (some operations are slowing down the process and
    %       could be restricted to sub-pieces of the signal to speed-up)
    %
    %     Copyright (C) 2019 Jérémy Signoret-Genest, DefenseCircuitsLab
    %     Original version: 04/12/2019
    %     Current version: 15/04/2021
    %
    %     Changelog (starting 15/04/2021)
    %       - 15/04/2021:
    %           . Added support for TDT files
    %
    %     This program is free software: you can redistribute it and/or modify
    %     it under the terms of the GNU General Public License as published by
    %     the Free Software Foundation, either version 3 of the License, or
    %     (at your option) any later version.
    %
    %     This program is distributed in the hope that it will be useful,
    %     but WITHOUT ANY WARRANTY; without even the implied warranty of
    %     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    %     GNU General Public License for more details.
    %
    %     You should have received a copy of the GNU General Public License
    %     along with this program.  If not, see <https://www.gnu.org/licenses/>.
    %
    
    
    properties(SetAccess = private, GetAccess = public, Hidden = false)
        AddedBeats
        Artefacts
        Extensions = {'pl2','nex','nex5','eeg','txt','mat','tev'};
        ExtensionFilter = '*.pl2;*.nex;*.nex5;*.eeg;*.txt;*.mat;*_Denoised.mat;*tev';
        Frequency
        HeartBeats
        HeartBeatsFile
        HeartRate
        LogFile
        MaxCorr
        Parameters
        Peaks
        Preprocessed
        RPeaks
        RangeShapes
        RemovedWindows
        Shapes
        RawFile
        RawValues
        RawFrequency
        RawTimes
        StartPath
        Template
        Times
    end
    
    properties(SetAccess = private, GetAccess = public, Hidden = true)
        Colors
        DefaultParameters
        Display
        Dragging
        Figure
        Handles
        IndxRmv
        LastFailed
        PartialReloadMode
        Previous
        ReloadMode
        Selected
        Scrolling = false;
        Slider
        SubEnhanced
        SubHR
        SubPeaks
        SubRaw
    end
    
    
    methods
        % Constructor
        function obj = ECG_Process
            obj.Colors = DefColors;
            % Parameters
            obj.Parameters.Default.Mouse = {
                'AutoUpdate',1;
                'BPEnable',1;
                'BPHigh', 180;
                'BPLow', 60;
                'Channel',[];
                'Discontinue', 1;
                'Outlier', 30;
                'Power', 4;
                'RPeaksEnable', false;
                'RPeaksFilter', true;
                'RPeakRange', 4;
                'ShapesEnable', 0;
                'SlidingWindowSize', 1;
                'SmoothDetection', 10;
                'SmoothKernel', 1000;
                'Species','Mouse';
                'StableIndex', 5;
                'SuspiciousFrequencyHigh', 15;
                'SuspiciousFrequencyLow', 8;
                'Threshold', 1e9;
                'Unit','BPM';
                'WaveformWindowLow', -15 ;
                'WaveformWindowHigh', 15
                };
            
            obj.Parameters.Default.Human = {
                'AutoUpdate',1;
                'BPEnable',1;
                'BPHigh', 180;
                'BPLow', 1;
                'Channel',[];
                'Discontinue',4;
                'Outlier', 240;
                'Power', 4;
                'RPeaksEnable', false;
                'RPeaksFilter', true;
                'RPeakRange', 20;
                'ShapesEnable', 0;
                'SlidingWindowSize', 5;
                'SmoothDetection', 20;
                'SmoothKernel', 1000;
                'Species','Human';
                'StableIndex', 50;
                'SuspiciousFrequencyHigh', 2; 
                'SuspiciousFrequencyLow', 1;
                'Threshold', 1e36;
                'Unit','BPM';
                'WaveformWindowLow', -150 ;
                'WaveformWindowHigh', 250
                };

            obj.RestoreDefault('Mouse');    

            % Prepare the GUI
            set(0,'Units','pixels')
            Scrsz = get(0,'ScreenSize');
            obj.Figure = figure('Position',[0 45 Scrsz(3) Scrsz(4)-75],'MenuBar','none','ToolBar','figure','Renderer','opengl');

            obj.SubRaw = subplot('Position',[0.06 0.075 0.65 0.15]);
            obj.SubEnhanced = subplot('Position',[0.06 0.23 0.65 0.15]);
            obj.SubPeaks = subplot('Position',[0.06 0.385 0.65 0.35]);
            obj.SubHR = subplot('Position',[0.06 0.74 0.65 0.225]);
            obj.Slider = subplot('Position',[0.06 0.97 0.65 0.025]);
            obj.Slider.YLim = [0 1];
            hold(obj.Slider,'on');
            if ~verLessThan('matlab','9.5')
                obj.Slider.Toolbar.Visible = 'off';
                disableDefaultInteractivity(obj.Slider);
            end
            obj.Handles.SliderLine = plot([10 10],[0 1],'Color','k','LineWidth',3.5,'ButtonDownFcn',{@(~,~)obj.SliderCB},'Parent',obj.Slider);
            obj.Slider.Color = 'w';
            obj.Slider.YColor = 'none';
            obj.Slider.XColor = 'none';
            linkaxes([obj.SubRaw obj.SubEnhanced obj.SubPeaks obj.SubHR],'x')
            
            UIBox(1) = subplot('Position',[0.72 0.075 0.25 0.125]);
            UIBox(2) = subplot('Position',[0.72 0.23 0.25 0.125]);
            plot([0.7575 0.7575],[0 1],'k--','LineWidth',1.5,'Parent',UIBox(2))
            UIBox(2).XLimMode = 'Manual';
            UIBox(2).YLimMode = 'Manual';
            UIBox(2).XLim = [0 1];
            UIBox(2).YLim = [0 1];
            UIBox(3) = subplot('Position',[0.72 0.385 0.25 0.325]);
            UIBox(4) = subplot('Position',[0.72 0.74 0.25 0.225]);
            
            for B = 1:4
                UIBox(B).Box = 'on';
                UIBox(B).XTick = [];
                UIBox(B).YTick = [];
                UIBox(B).LineWidth = 2;
            end

            uicontrol('Style','pushbutton','String','Pre-processing','FontSize',14,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.72+0.075 0.185 0.1 0.03],'HorizontalAlignment','center','BackgroundColor','w','Enable','inactive');
            uicontrol('Style','pushbutton','String','Detection','FontSize',14,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.72+0.075 0.34 0.1 0.03],'HorizontalAlignment','center','BackgroundColor','w','Enable','inactive');
            uicontrol('Style','pushbutton','String','Corrections','FontSize',14,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.72+0.075 0.695 0.1 0.03],'HorizontalAlignment','center','BackgroundColor','w','Enable','inactive');
            uicontrol('Style','pushbutton','String','Heart rate','FontSize',14,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.72+0.075 0.95 0.1 0.03],'HorizontalAlignment','center','BackgroundColor','w','Enable','inactive');
            
            % Current file
            obj.Handles.CurrentFile = uicontrol('Style','text','String','','FontSize',14,'FontName','Arial','FontWeight','normal',...
               'Units','Normalized','Position',[0.72 0.04 0.25 0.03],'HorizontalAlignment','left');
            
            
            % Pre-processing
            uicontrol('Style','text','String','Kernel size for drift estimation','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.73 0.14 0.16 0.03],'HorizontalAlignment','right','BackgroundColor','w');
            obj.Handles.BPCheckBox = uicontrol('Style','checkbox','String',' Bandpass filtering','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.BPEnableCB},'Units','Normalized','Position',[0.75 0.095 0.12 0.03],'BackgroundColor','w','Value',obj.Parameters.BPEnable);
            uicontrol('Style','text','String','Low','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.87 0.105 0.04 0.03],'HorizontalAlignment','left','BackgroundColor','w');
            uicontrol('Style','text','String','High','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.87 0.075 0.04 0.03],'HorizontalAlignment','left','BackgroundColor','w');
            obj.Handles.SmoothKernel.Edit = uicontrol('Style','edit','String',obj.Parameters.SmoothKernel,'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.SmoothKernelEditCB},'Units','Normalized','Position',[0.9 0.145 0.04 0.03],'HorizontalAlignment','center');
            obj.Handles.BPHigh.Edit = uicontrol('Style','edit','String',obj.Parameters.BPHigh,'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.BPHighEditCB},'Units','Normalized','Position',[0.9 0.08 0.04 0.03],'HorizontalAlignment','center');
            obj.Handles.BPLow.Edit = uicontrol('Style','edit','String',obj.Parameters.BPLow,'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.BPLowEditCB},'Units','Normalized','Position',[0.9 0.11 0.04 0.03],'HorizontalAlignment','center');
            % NB: all the "Set" buttons are in theory useless, but since
            % the callbacks for the edit boxes are executed only when
            % clicking outside, this prevents any over-questionning 
            obj.Handles.SmoothKernel.Set = uicontrol('Style','pushbutton','String','Set','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.SmoothKernelEditCB},'Units','Normalized','Position',[0.94 0.145 0.025 0.03],'HorizontalAlignment','center');
            obj.Handles.BPSet = uicontrol('Style','pushbutton','String','Set','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.BPSetCB},'Units','Normalized','Position',[0.94 0.095 0.025 0.03],'HorizontalAlignment','center');
   
            % Detection
            uicontrol('Style','text','String','Power','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.73 0.295 0.065 0.03],'HorizontalAlignment','right','BackgroundColor','w');
            uicontrol('Style','text','String','Threshold','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.73 0.265 0.065 0.03],'HorizontalAlignment','right','BackgroundColor','w');
            uicontrol('Style','text','String','Smoothing','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.73 0.235 0.065 0.03],'HorizontalAlignment','right','BackgroundColor','w');
            uicontrol('Style','text','String','Window','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.915 0.295 0.05 0.03],'HorizontalAlignment','center','BackgroundColor','w');
            
            obj.Handles.Power.Edit = uicontrol('Style','edit','String',num2str(obj.Parameters.Power),'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.PowerEditCB},'Units','Normalized','Position',[0.8 0.2975 0.04 0.03],'HorizontalAlignment','center','BackgroundColor','w');
            obj.Handles.Threshold.Edit = uicontrol('Style','edit','String',num2str(obj.Parameters.Threshold,3),'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.ThresholdEditCB},'Units','Normalized','Position',[0.8 0.2675 0.065 0.03],'HorizontalAlignment','center','BackgroundColor','w');
            obj.Handles.SmoothDetection.Edit = uicontrol('Style','edit','String',num2str(obj.Parameters.SmoothDetection),'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.SmoothDetectionEditCB},'Units','Normalized','Position',[0.8 0.2375 0.04 0.03],'HorizontalAlignment','center','BackgroundColor','w');
            obj.Handles.WaveformWindowLow.Edit = uicontrol('Style','edit','String',num2str(obj.Parameters.WaveformWindowLow),'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.WaveformWindowLowEditCB},'Units','Normalized','Position',[0.915 0.2675 0.025 0.03],'HorizontalAlignment','center','BackgroundColor','w');
            obj.Handles.WaveformWindowHigh.Edit = uicontrol('Style','edit','String',num2str(obj.Parameters.WaveformWindowHigh),'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.WaveformWindowHighEditCB},'Units','Normalized','Position',[0.94 0.2675 0.025 0.03],'HorizontalAlignment','center','BackgroundColor','w');
                    
            obj.Handles.Power.Set = uicontrol('Style','pushbutton','String','Set','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.PowerEditCB},'Units','Normalized','Position',[0.84 0.2975 0.025 0.03],'HorizontalAlignment','center');
            obj.Handles.Threshold.Set = uicontrol('Style','pushbutton','String','Set','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.ThresholdSetCB},'Units','Normalized','Position',[0.865 0.2675 0.025 0.03],'HorizontalAlignment','center');
            obj.Handles.SmoothDetection.Set = uicontrol('Style','pushbutton','String','Set','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.SmoothDetectionEditCB},'Units','Normalized','Position',[0.84 0.2375 0.025 0.03],'HorizontalAlignment','center');
            obj.Handles.WindowLH.Set = uicontrol('Style','pushbutton','String','Set','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.WindowLHSetCB},'Units','Normalized','Position',[0.9275 0.2375 0.025 0.03],'HorizontalAlignment','center');

            % Manual interventions
            DCol = DefColors;
            obj.Handles.StartPath = uicontrol('Style','pushbutton','String','Start Path','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.StartPathCB},'Units','Normalized','Position',[0.725 0.395 0.06 0.04],'HorizontalAlignment','center');
            obj.Handles.Load = uicontrol('Style','pushbutton','String','Load file','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.LoadCB},'Units','Normalized','Position',[0.785 0.395 0.06 0.04],'HorizontalAlignment','center','BackgroundColor',DCol(2,:)+0.1);
            obj.Handles.Save= uicontrol('Style','pushbutton','String','Save','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.SaveCB},'Units','Normalized','Position',[0.845 0.395 0.06 0.04],'HorizontalAlignment','center');
            obj.Handles.Exit = uicontrol('Style','pushbutton','String','Exit','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.ExitCB},'Units','Normalized','Position',[0.905 0.395 0.06 0.04],'HorizontalAlignment','center');
            
            obj.Handles.LockX = uicontrol('Style','checkbox','String','Lock X axes','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.LockXCB},'Units','Normalized','Position',[0.725 0.52 0.12 0.04],'HorizontalAlignment','center','BackgroundColor','w');
            obj.Handles.LockY = uicontrol('Style','checkbox','String','Lock Y axes','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.LockYCB},'Units','Normalized','Position',[0.725 0.47 0.12 0.04],'HorizontalAlignment','center','BackgroundColor','w');
            obj.Handles.EnableShapes = uicontrol('Style','checkbox','String','Plot waveforms','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.EnableShapesCB},'Value',obj.Parameters.ShapesEnable,'Units','Normalized','Position',[0.725 0.57 0.12 0.04],'HorizontalAlignment','center','BackgroundColor','w');
            obj.Handles.RPeaksEnable = uicontrol('Style','checkbox','String','Plot RPeaks','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.RPeaksEnableCB},'Value',obj.Parameters.RPeaksEnable,'Units','Normalized','Position',[0.725 0.62 0.12 0.04],'HorizontalAlignment','center','BackgroundColor','w');
%
            

            obj.Handles.Process = uicontrol('Style','pushbutton','String','Run algorithm','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.ProcessCB},'Units','Normalized','Position',[0.845 0.62 0.12 0.04],'HorizontalAlignment','center','BackgroundColor',DCol(1,:)+0.1);
%             obj.Handles.AddSingleBeat = uicontrol('Style','pushbutton','String','Add single beat','FontSize',16,'FontName','Arial','FontWeight','bold',...
%                 'Callback',{@(~,~)obj.AddSingleBeatCB},'Units','Normalized','Position',[0.845 0.62 0.12 0.04],'HorizontalAlignment','center');
%             obj.Handles.DeleteBeat = uicontrol('Style','pushbutton','String','Delete selected beat','FontSize',16,'FontName','Arial','FontWeight','bold',...
%                 'Callback',{@(~,~)obj.DeleteBeatCB},'Units','Normalized','Position',[0.845 0.57 0.12 0.04],'HorizontalAlignment','center');
            obj.Handles.AddRange = uicontrol('Style','pushbutton','String','Add exclusion range','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.AddRangeCB},'Units','Normalized','Position',[0.845 0.52 0.12 0.04],'HorizontalAlignment','center');
            obj.Handles.DeleteRange = uicontrol('Style','pushbutton','String','Delete selected range','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.DeleteRangeCB},'Units','Normalized','Position',[0.845 0.47 0.12 0.04],'HorizontalAlignment','center');
            
            % Heart rate
            uicontrol('Style','text','String','Window size','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.7275 0.8875 0.07 0.03],'HorizontalAlignment','right','BackgroundColor','w');
            obj.Handles.SlidingWindowSize.Edit = uicontrol('Style','edit','String',obj.Parameters.SlidingWindowSize,'FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.SlidingWindowSizeEditCB},'Units','Normalized','Position',[0.80 0.89 0.04 0.03],'HorizontalAlignment','center');
            obj.Handles.SlidingWindowSize.Set = uicontrol('Style','pushbutton','String','Set','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.SlidingWindowSizeEditCB},'Units','Normalized','Position',[0.84 0.89 0.025 0.03],'HorizontalAlignment','center');
            obj.Handles.AutoUpdateHR = uicontrol('Style','checkbox','String',' AutoUpdate','FontSize',12,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.AutoUpdateHRCB},'Value',obj.Parameters.AutoUpdate,'Units','Normalized','Position',[0.905 0.855 0.06 0.04],'BackgroundColor','w');
            obj.Handles.UpdateHeartRate = uicontrol('Style','pushbutton','String','Update','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.ProcessHeartRate},'Units','Normalized','Position',[0.905 0.885 0.06 0.04],'HorizontalAlignment','center');
            
            uicontrol('Style','text','String','Unit','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Units','Normalized','Position',[0.73125 0.83 0.04 0.03],'HorizontalAlignment','left','BackgroundColor','w');
            obj.Handles.BPM = uicontrol('Style','checkbox','String',' Beats per minute (BPM)','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.BPMCB},'Units','Normalized','Position',[0.77 0.83 0.15 0.03],'BackgroundColor','w');
            obj.Handles.Hz = uicontrol('Style','checkbox','String',' Beats per second (Hz)','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.HzCB},'Units','Normalized','Position',[0.77 0.79 0.15 0.03],'BackgroundColor','w');
            obj.Handles.RestoreView = uicontrol('Style','pushbutton','String','Restore view','FontSize',16,'FontName','Arial','FontWeight','bold',...
                'Callback',{@(~,~)obj.RestoreView},'Units','Normalized','Position',[0.73 0.745 0.075 0.04],'HorizontalAlignment','center');
            
             if strcmpi(obj.Parameters.Unit,'BPM')
                 obj.Handles.BPM.Value = 1;
             else
                 obj.Handles.Hz.Value = 1;
             end
            
            obj.Handles.ZoomSubEnhanced = zoom(obj.SubEnhanced);
            obj.Handles.ZoomSubHR.Motion = zoom(obj.SubHR);
            obj.Handles.ZoomSubPeaks.Motion = zoom(obj.SubPeaks);
            obj.Handles.ZoomSubRaw.Motion = zoom(obj.SubRaw);
            obj.Handles.ZoomSubHR.Motion.ActionPostCallback = @(~,~)obj.EvaluateWindow;
            obj.Handles.ZoomSubPeaks.Motion.ActionPostCallback = @(~,~)obj.EvaluateWindow;
            obj.Handles.ZoomSubRaw.Motion.ActionPostCallback = @(~,~)obj.EvaluateWindow;
            obj.Handles.ZoomSubHR.Motion.ActionPostCallback = @(~,~)obj.EvaluateWindow;
            obj.SubplotVisual;
            obj.DisableAll;
            obj.Handles.Load.Enable = 'on';
            obj.Handles.StartPath.Enable = 'on';
            obj.Handles.Exit.Enable = 'on';
        end
    end
    
    methods(Hidden)
        function RestoreDefault(obj,Species)
            if strcmpi(Species,'Mouse')
                for F = 1 : size(obj.Parameters.Default.Mouse,1)
                    obj.Parameters.(obj.Parameters.Default.Mouse{F,1}) = obj.Parameters.Default.Mouse{F,2};
                end
            elseif strcmpi(Species,'Human')
                for F = 1 : size(obj.Parameters.Default.Human,1)
                    obj.Parameters.(obj.Parameters.Default.Human{F,1}) = obj.Parameters.Default.Human{F,2};
                end
            end
            obj.ApplyParameters;
        end
        function ApplyParameters(obj)
            obj.Handles.BPCheckBox.Value = obj.Parameters.BPEnable;
            obj.Handles.BPHigh.Edit.String = num2str(obj.Parameters.BPHigh);
            obj.Handles.BPLow.Edit.String = num2str(obj.Parameters.BPLow);
            obj.Handles.EnableShapes.Value = obj.Parameters.ShapesEnable;
            obj.Handles.Power.Edit.String = num2str(obj.Parameters.Power);
            obj.Handles.SlidingWindowSize.Edit.String = num2str(obj.Parameters.SlidingWindowSize);
            obj.Handles.SmoothKernel.Edit.String = num2str(obj.Parameters.SmoothKernel);
            obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Threshold,3);
            obj.Handles.AutoUpdateHR.Value = obj.Parameters.AutoUpdate;
            obj.Handles.SmoothDetection.Edit.String = num2str(obj.Parameters.SmoothDetection);
            obj.Handles.WaveformWindowLow.Edit.String = num2str(obj.Parameters.WaveformWindowLow);
            obj.Handles.WaveformWindowHigh.Edit.String = num2str(obj.Parameters.WaveformWindowHigh);
        end
        
        function SubplotVisual(obj)
            obj.SubRaw.LineWidth = 2;
            obj.SubRaw.FontSize = 12;
            obj.SubRaw.FontWeight = 'b';
            obj.SubRaw.TickDir = 'out';
            obj.SubRaw.XLabel.String = 'Time (s)';
            obj.SubRaw.XLabel.FontSize = 17;
            obj.SubRaw.YLabel.String = 'Raw ECG';
            obj.SubRaw.YLabel.FontSize = 17;
            obj.SubRaw.YTick = [];
            obj.SubRaw.Box = 'off';
            
            obj.SubEnhanced.LineWidth = 2;
            obj.SubEnhanced.XColor = 'none';
            obj.SubEnhanced.YLabel.String = 'Enhanced ECG';
            obj.SubEnhanced.FontSize = 12;
            obj.SubEnhanced.FontWeight = 'b';
            obj.SubEnhanced.TickDir = 'out';
            obj.SubEnhanced.YLabel.FontSize = 17;
            obj.SubEnhanced.YTick = [];
            obj.SubEnhanced.Box = 'off';
            
            obj.SubPeaks.LineWidth = 2;
            obj.SubPeaks.XColor = 'none';
            obj.SubPeaks.YLabel.String = 'ECG';
            obj.SubPeaks.FontSize = 12;
            obj.SubPeaks.FontWeight = 'b';
            obj.SubPeaks.TickDir = 'out';
            obj.SubPeaks.YLabel.FontSize = 17;
            obj.SubPeaks.YTick = [];
            obj.SubPeaks.Box = 'off';
            
            obj.SubHR.LineWidth = 2;
            obj.SubHR.XColor = 'none';
            if strcmpi(obj.Parameters.Unit,'BPM')
                obj.SubHR.YLabel.String = 'Heart rate (BPM)';
            else
                obj.SubHR.YLabel.String = 'Heart rate (Hz)';
            end
            obj.SubHR.FontSize = 12;
            obj.SubHR.FontWeight = 'b';
            obj.SubHR.TickDir = 'out';
            obj.SubHR.YLabel.FontSize = 17;
            obj.SubHR.Box = 'off';
            
            if ~isempty(obj.Times)
                if obj.SubHR.XLim(2)>obj.Times(end)
                    obj.SubHR.XLim(2) = obj.Times(end);
                end
            end
            
            obj.Figure.KeyPressFcn = {@(Src,Key)obj.KeyPressCB(Src,Key)};
            drawnow
        end
        
        function RestoreView(obj)
           if ~isempty(obj.Times)
               obj.SubHR.XLim = obj.Times([1 end]);
               obj.SubHR.YLimMode = 'auto';
               drawnow
               obj.SubHR.YLimMode = 'manual';
           end
        end

        function KeyPressCB(obj,Src,Key)
            if ~obj.Scrolling
                obj.Scrolling = true;
                if strcmpi(Key.Key,'rightarrow')
                    if (obj.SubHR.XLim(2) + 0.25*diff(obj.SubHR.XLim)<=obj.Times(end))
                        obj.SubHR.XLim = obj.SubHR.XLim + 0.25*diff(obj.SubHR.XLim);
                        obj.Handles.SliderLine.XData = [1 1] * obj.SubHR.XLim(1) + 0.5*diff(obj.SubHR.XLim);
                        drawnow;
                    else
                        obj.SubHR.XLim = [obj.Times(end)-diff(obj.SubHR.XLim) obj.Times(end)];
                        obj.Handles.SliderLine.XData = [1 1] * obj.SubHR.XLim(1);
                        drawnow;
                    end
                elseif strcmpi(Key.Key,'leftarrow')
                    if (obj.SubHR.XLim(1) - 0.25*diff(obj.SubHR.XLim)>=obj.Times(1))
                        obj.SubHR.XLim = obj.SubHR.XLim - 0.25*diff(obj.SubHR.XLim);
                        obj.Handles.SliderLine.XData = [1 1] * obj.SubHR.XLim(1) + 0.5*diff(obj.SubHR.XLim);
                        drawnow;
                    else
                        obj.SubHR.XLim = [obj.Times(1) obj.Times(1)+diff(obj.SubHR.XLim)];
                        obj.Handles.SliderLine.XData = [1 1] * obj.SubHR.XLim(2);
                        drawnow;
                    end
                end
                obj.Scrolling = false;
            end
        end
        
        function LoadCB(obj)
            % Prompt to choose a file:
            %    - _HeartBeats.mat for previously processed session
            %    - any supported format for ECG (can be added easily)
            obj.DisableAll;
            PartialReloadMode = false;
            drawnow
            [File,Path] = uigetfile({[obj.StartPath '*_HeartBeats.mat;' obj.ExtensionFilter]},'Please select a file to process.');
            if File == 0
                if isempty(obj.RawFile)
                    obj.Handles.Load.Enable = 'on';
                    obj.Handles.StartPath.Enable = 'on';
                    obj.Handles.Exit.Enable = 'on';
                else
                    obj.EnableAll;
                end
                return
            else
               [~,Basename,Ext] = fileparts(File);
               if contains(File,'_HeartBeats.mat')
                   Basename = strsplit(Basename,'_HeartBeats');
                   Basename = Basename{1};
                   % Retrieve raw file
                    % We don't really expect two ECG files with the same
                    % basename and a different extension... but just in
                    % case
                    Index = [];
                    Names = {};
                    Ext = {};
                   for E = 1 : numel(obj.Extensions),
                      if exist([Path Basename '.' obj.Extensions{E}],'file'),
                          Index = [Index;E];
                          Names = [Names;Basename '.' obj.Extensions{E}];
                          Ext = [Ext; '.' obj.Extensions{E}];
                      end
                   end
                   if isempty(Index)
                       Wn = warndlg(['No matching raw file found for the session.' newline 'Aborting.']);
                       waitfor(Wn)
                       obj.EnableAll;
                       return
                   elseif numel(Index)>1
                       Answer = listdlg('PromptString',{'Several matching raw ECG files were found (?!).','Please choose.'},'ListString',Names,'SelectionMode','single','ListSize',[250 300]);
                       if isempty(Answer)
                           obj.EnableAll;
                           return
                       end
                       Names = Names(Answer,:);
                       Ext = Ext(Answer,:);
                   end
                   HeartBeatsFile = fullfile(Path,File);
                   LogFile = fullfile(Path,[Basename '_ECGLog.mat']);
                   RawFile = fullfile(Path,Names{1});
                   Ext = Ext{1};
                   PartialReloadMode = false;
                   % If the heartbeat file is present so should the
                   % logfile... but just in case
                   if ~exist(LogFile,'file')
                       Loaded_HeartbeatsFile = load(HeartBeatsFile);
                       HeartBeats = Loaded_HeartbeatsFile.HeartBeats;
                       ReloadMode = false;
                       PartialReloadMode = true;
                       Wn = warndlg(['No matching log file found for the session.' newline 'Peaks loaded, but previous ECG preprocessing ignored. Default parameters loaded instead.']);
                       waitfor(Wn)
                   else
                       % Get the beats times in memory
                       Loaded_HeartbeatsFile = load(HeartBeatsFile);
                       HeartBeats = Loaded_HeartbeatsFile.HeartBeats;
                       ReloadMode = true;
                       Loaded_LogFile = load(LogFile); 
                   end
               else
                   RawFile = fullfile(Path,File);
                   LogFile = fullfile(Path,[Basename '_ECGLog.mat']);
                   HeartBeatsFile = [Path Basename '_HeartBeats.mat'];
                   % First check whether it was processed before
                   ReloadMode = false;
                   if exist(HeartBeatsFile,'file')
                       Answer = questdlg('This file was already processed, do you wish to continue anyway?','Please choose...','Yes (Start again)','Yes (Load previously processed)','No (abort)','Yes (Start again)');
                       if strcmpi(Answer,'No (abort)')
                           obj.EnableAll;
                           return
                       elseif strcmpi(Answer,'Yes (Load previously processed)')
                           % If the heartbeat file is present so should the
                           % logfile... but just in case
                           if ~exist(LogFile,'file')
                               Wn = warndlg(['No matching log file found for the session.' newline 'Default parameters loaded, previous analysis ignored.']);
                               waitfor(Wn)
                           else
                               ReloadMode = true;
                           end
                       end
                       waitfor(Answer)
                   end
               end
               Channel = [];
               Frag = 0;
                   switch lower(Ext)
                       case '.pl2'
                           Species = 'Mouse';
                           % Retrieve channels
                           if ReloadMode,
                               Loaded_LogFile = load(LogFile);
                               % Legacy
                               if isfield(Loaded_LogFile,'Parameters')
                                   ChanPlexon = Loaded_LogFile.Parameters.Channel;
                               elseif isfield(Loaded_LogFile,'Channel')
                                   ChanPlexon = Loaded_LogFile.Channel;
                               end
                           else
                               Pl2_Index = PL2GetFileIndex(RawFile);
                               Analog_Index = arrayfun(@(x) (~(Pl2_Index.AnalogChannels{x}.NumValues == 0)) & strcmpi(Pl2_Index.AnalogChannels{x}.SourceName,'AI'),1:numel(Pl2_Index.AnalogChannels));
                               Analog_Channels = arrayfun(@(x) (Pl2_Index.AnalogChannels{x}.Channel), find(Analog_Index));
                               Analog_Channels = [(find(Analog_Index))',...
                                   Pl2_Index.AnalogChannels{find(Analog_Index,1)}.Source * ones(numel(Analog_Channels),1),...
                                   Analog_Channels'];
                               
                               % Choose channel
                               [IndexChannel] = listdlg('PromptString','Select the ECG channel to use:',...
                                   'SelectionMode','single',...
                                   'ListString',num2str(Analog_Channels(:,3)));
                               if isempty(IndexChannel)
                                   if isempty(obj.RawFile)
                                       obj.Handles.Load.Enable = 'on';
                                       obj.Handles.StartPath.Enable = 'on';
                                       obj.Handles.Exit.Enable = 'on';
                                   else
                                       obj.EnableAll;
                                   end
                                   return
                               else
                                   ChanPlexon = Analog_Channels(IndexChannel,1);
                               end
                           end
                           % Load data
                           Channel = ChanPlexon;
                           ECG = PL2Ad(RawFile,ChanPlexon);
                           RawValues = ECG.Values;
                           RawFrequency = ECG.ADFreq;
                           RawTimes = ECG.FragTs : (1 / ECG.ADFreq) : ((ECG.FragCounts-1) / ECG.ADFreq + ECG.FragTs);
                           Frag = ECG.FragTs;
                           
                       case '.tev'
                           Species = 'Mouse';
                           % Retrieve channels
                           if ReloadMode
                               Loaded_LogFile = load(LogFile);
                               % Legacy
                               if isfield(Loaded_LogFile,'Parameters')
                                   ChanTDT = Loaded_LogFile.Parameters.Channel;
                               elseif isfield(Loaded_LogFile,'Channel')
                                   ChanTDT = Loaded_LogFile.Channel;
                               end
                           else
                               addpath(genpath('F:\MATLAB\Common\SDKs\TDTSDK\'))
                               TDTData = TDTbin2mat(Path);
                               Fields = fields(TDTData.streams);
                               Fields = Fields(contains(Fields,'ECG'));
                               if isempty(Fields)
                                   if isempty(obj.RawFile)
                                       obj.Handles.Load.Enable = 'on';
                                       obj.Handles.StartPath.Enable = 'on';
                                       obj.Handles.Exit.Enable = 'on';
                                   else
                                       obj.EnableAll;
                                   end
                                   return
                               end
                               
                               % Choose channel
                               [IndexChannel] = listdlg('PromptString','Select the ECG channel to use:',...
                                   'SelectionMode','single',...
                                   'ListString',Fields);
                               if isempty(IndexChannel)
                                   if isempty(obj.RawFile)
                                       obj.Handles.Load.Enable = 'on';
                                       obj.Handles.StartPath.Enable = 'on';
                                       obj.Handles.Exit.Enable = 'on';
                                   else
                                       obj.EnableAll;
                                   end
                                   return
                               else
                                   ChanTDT = Fields{IndexChannel};
                               end
                           end
                           % Load data
                           Channel = ChanTDT;
                           ECG = TDTData.streams.(Channel);
                           RawValues = double(ECG.data)';
                           RawFrequency = ECG.fs;
                           RawTimes = ECG.startTime : (1 / ECG.fs) : ((numel(ECG.data)-1)*1/ECG.fs+ECG.startTime);
                           Frag = ECG.startTime;
                           
                       case '.nex'
                           Species = 'Mouse';
                       case '.nex5'
                           Species = 'Mouse';
                       case '.mat'
                           if contains(Basename,'Denoised')
                               Species = 'Mouse';
                               RawLoaded = load(RawFile);
                               RawValues = RawLoaded.Values;
                               RawTimes = RawLoaded.Times;
                               RawFrequency = RawLoaded.Frequency;
                           else
                               % Loose way of checking whether it was rewritten
                               % from a known source (e.g. .acq so far)
                               Cont = true;
                               RawLoaded = load(RawFile);
                               
                               if isfield(RawLoaded,'channels')
                                   if ~isfield(channels{1,2},'name')
                                       Cont = false;
                                   else
                                       if ~(any(strfind(channels{1,2}.name,'ecg')))
                                           Cont = false;
                                       end
                                   end
                               else Cont = false;
                               end
                               if Cont
                                   Species = 'Human';
                                   RawFrequency = RawLoaded.channels{1,2}.samples_per_second;
                                   RawValues = RawLoaded.channels{1,2}.data;
                                   RawTimes = 1/RawFrequency:1/RawFrequency:1/RawFrequency*numel(RawValues);
                               elseif isfield(RawLoaded,'data') && isfield(RawLoaded,'datastart')
                                   Species = 'Mouse';
                                   % data exported as .mat from labchart
                                   % Split channels
                                   DataAllChannels = [];
                                   for C = 1 : size(RawLoaded.datastart,1)
                                       if RawLoaded.datastart(C,1)~=-1
                                           DataC = cell2mat(arrayfun(@(x) RawLoaded.data(RawLoaded.datastart(C,x):RawLoaded.dataend(C,x)),1:numel(RawLoaded.datastart(C,:)),'UniformOutput',false));
                                           if isempty(DataAllChannels)
                                               DataAllChannels = NaN(size(RawLoaded.datastart,1),numel(DataC));
                                           end
                                           DataAllChannels(C,:) = DataC;
                                       end
                                   end
                                   RawFrequency = RawLoaded.samplerate(5);
                                   RawValues = (DataAllChannels(5,:))';
                                   RawTimes = (1/RawFrequency+RawLoaded.firstsampleoffset(5))/RawFrequency:1/RawFrequency:1/RawFrequency*numel(RawValues);
                               else
                                   Wn = warndlg(['The text file was exported from an unknown system.' newline 'Aborting.']);
                                   waitfor(Wn)
                                   obj.EnableAll;
                                   return
                               end
                           end
                       case '.txt'
                           Species = 'Human';
                           % Adapted for recordings from Würzburg
                           % psychology(structure from export from .acq
                           % files)
                           
                           % Check that it's actually exported from .acq
                           FO = fopen(RawFile,'r');
                           if ~contains(fgetl(FO),'acq')
                               Wn = warndlg(['The text file was exported from an unknown system.' newline 'Aborting.']);
                               waitfor(Wn)
                               obj.EnableAll;
                               return
                           else
                               SR = fgetl(FO);
                               RawFrequency = strsplit(SR,' ');
                               RawFrequency = 1/str2double(RawFrequency{1});
                               if contains(SR,'msec')
                                   RawFrequency = RawFrequency*1000;
                               else
                                   Wn = warndlg(['Unexpected ECG unit format. Add a case to the code.' newline 'Aborting.']);
                                   waitfor(Wn)
                                   obj.EnableAll;
                                   return
                               end
                               FR = readtable(RawFile);
                               RawValues = (FR.CH2(2:end))';
                               RawTimes = 1/RawFrequency:1/RawFrequency:1/RawFrequency*FR.CH2(1);
                           end
                       case '.eeg'
                           Species = 'Human';
                           % Adapted for the generalization protocols at
                           % UKW; other .eeg files could be organized
                           % differently
                           FO = fopen(RawFile,'r');
                           FR = fread(FO,inf,'float32',0,'l');
                           ECG = FR(2:6:end)-FR(1:6:end);
                           RawValues = ECG(1:end-2000); % Drop at the end
                           
                           % Try to retrieve the frequency from associated
                           % logfiles
                           HeaderFile = [Path  Basename '.AHDR'];
                           if exist(HeaderFile,'file')==2
                               FO = fopen(HeaderFile,'r','a','UTF-8');
                               FR = fscanf(FO,'%c');
                               Lines = strsplit(FR,newline);
                               SR = strsplit(Lines{contains(Lines,'Sampling Rate [Hz]:')},'Sampling Rate [Hz]:');
                               SR = str2double(SR{2});
                               RawFrequency = SR;
                           else
                               SR = inputdlg(['Sampling rate could not be retrieved from an AHDR file.' newline 'Please indicate the sampling rate.'],'Sampling rate?',[1 40],{'1000'});
                               if any(isnan(str2double(SR))) | isempty(SR),
                                   obj.EnableAll;
                                   return
                               end
                           end
                           RawTimes = 1 / RawFrequency : 1/RawFrequency : 1/RawFrequency*numel(RawValues);
                   end
                   if ReloadMode || PartialReloadMode,
                       % Get the beats times in memory
                       Loaded_HeartbeatsFile = load(HeartBeatsFile);
                       obj.HeartBeats = Loaded_HeartbeatsFile.HeartBeats;
                       % Legacy/conversion
                       if numel(obj.HeartBeats(:,1))>1
                           obj.HeartBeats = obj.HeartBeats';
                       end
                       if isfield(Loaded_HeartbeatsFile,'InterpolatedWindows')
                           if isfield(Loaded_HeartbeatsFile,'RemovedWindows')
                               obj.RemovedWindows = [Loaded_HeartbeatsFile.RemovedWindows;Loaded_HeartbeatsFile.InterpolatedWindows];
                               [~,IndxSortW] = sort([obj.RemovedWindows(:,1)]);
                               obj.RemovedWindows = obj.RemovedWindows(IndxSortW,:);
                           else
                               obj.RemovedWindows = Loaded_HeartbeatsFile.InterpolatedWindows;
                           end
                       else
                           obj.RemovedWindows = Loaded_HeartbeatsFile.RemovedWindows;
                       end
                       if isfield(Loaded_HeartbeatsFile,'AddedBeats')
                           if numel(Loaded_HeartbeatsFile.AddedBeats(:,1))>1
                               Loaded_HeartbeatsFile.AddedBeats = Loaded_HeartbeatsFile.AddedBeats';
                           end
                           obj.HeartBeats = sort([obj.HeartBeats,Loaded_HeartbeatsFile.AddedBeats]);
                       end
                       if isfield(Loaded_HeartbeatsFile,'RPeaks')
                           obj.RPeaks = Loaded_HeartbeatsFile.RPeaks;
                       else
                           obj.RPeaks = [];
                       end
                       if isfield(Loaded_HeartbeatsFile,'Artefacts') && ReloadMode
                           obj.Artefacts = Loaded_HeartbeatsFile.Artefacts;
                       end
                       if ReloadMode,
                           Loaded_LogFile = load(LogFile);
                           % Legacy
                           if ~isfield(Loaded_LogFile,'Parameters')
                               Loaded_LogFileTemp = Loaded_LogFile;
                               Loaded_LogFile = [];
                               Loaded_LogFile.Parameters = Loaded_LogFileTemp;
                           end
                           % Reapply parameters
                           % Reattribute values one by one in case we change the
                           % structure at some point (to prevent any missing property)
                           Fields = fieldnames(Loaded_LogFile.Parameters);
                           for F = 1 : numel(Fields)
                               if isfield(obj.Parameters,Fields{F})
                                   obj.Parameters.(Fields{F}) = Loaded_LogFile.Parameters.(Fields{F});
                               end
                           end
                           obj.ApplyParameters;
                       end
                   else
                       obj.RemovedWindows = [];
                   end
                   if strcmpi(Species,'Human') && ~strcmpi(obj.Parameters.Species,'Human') && ~ReloadMode
                      obj.RestoreDefault('Human');
                   elseif strcmpi(Species,'Mouse') && ~strcmpi(obj.Parameters.Species,'Mouse') && ~ReloadMode
                       obj.RestoreDefault('Mouse');
                   end
                   if  obj.Parameters.RPeaksEnable
                       obj.Handles.RPeaksEnable.Value = 1;
                   end
                   obj.Parameters.Species = Species;
                   obj.Parameters.Channel = Channel;
                   obj.Parameters.Frag = Frag;
                   obj.ReloadMode = ReloadMode;
                   obj.PartialReloadMode = PartialReloadMode;
                   obj.RawFile = RawFile;
                   obj.RawFrequency = RawFrequency;
                   obj.RawTimes = RawTimes;
                   obj.RawValues = RawValues;
                   obj.HeartBeatsFile = HeartBeatsFile;
                   obj.LogFile = LogFile;
                   obj.AutoLims;
                   obj.Preprocess('Force');
                   obj.Handles.CurrentFile.String = Basename;
            end
        end
        
        
        function EnableAll(obj)
            Fields = fields(obj.Handles);
            Fields = Fields(~contains(Fields,'ZoomSub')&~contains(Fields,'FillRemove'));
            for F = 1 : numel(Fields)
                if ~isempty(obj.Handles.(Fields{F}))
                    SubFields = fields(obj.Handles.(Fields{F}));
                    if any(contains(SubFields,'Enable'))
                        obj.Handles.(Fields{F}).Enable = 'on';
                    else
                        for SF = 1 : numel(SubFields)
                            try
                                obj.Handles.(Fields{F}).(SubFields{SF}).Enable = 'on'; % Lazy temporary solution
                            end
                        end
                    end
                end
            end
            obj.Figure.KeyPressFcn = {@(Src,Key)obj.KeyPressCB(Src,Key)};
            drawnow
        end
        
        function obj = DisableAll(obj)
            Fields = fields(obj.Handles);
            Fields = Fields(~contains(Fields,'ZoomSub')&~contains(Fields,'FillRemove'));
            for F = 1 : numel(Fields)
                if ~isempty(obj.Handles.(Fields{F}))
                    SubFields = fields(obj.Handles.(Fields{F}));
                    if any(contains(SubFields,'Enable'))
                        obj.Handles.(Fields{F}).Enable = 'off';
                    else
                        for SF = 1 : numel(SubFields)
                            try
                                obj.Handles.(Fields{F}).(SubFields{SF}).Enable = 'off'; % Lazy temporary solution
                            end
                        end
                    end
                end
            end
            obj.Figure.KeyPressFcn = [];
            drawnow
        end
        
        function StartPathCB(obj)
            StartPath = uigetdir;
            if StartPath~=0
                obj.StartPath = [StartPath filesep];
            end
        end
        
        %% Parameters callbacks
        % Pre-processing
        
        function SmoothKernelEditCB(obj)
            if str2double(obj.Handles.SmoothKernel.Edit.String)>0
                % If too large, the smooth function will take care of the
                % error
                obj.Parameters.SmoothKernel = str2double(obj.Handles.SmoothKernel.Edit.String);
                obj.Preprocess;
            else
                obj.Handles.SmoothKernel.Edit.String = num2str(obj.Parameters.SmoothKernel);
            end
        end
        
        function BPEnableCB(obj)
            obj.Parameters.BPEnable =  obj.Handles.BPCheckBox.Value;
            obj.Preprocess;
        end
        
        function BPHighEditCB(obj)
            if str2double(obj.Handles.BPHigh.Edit.String)>0 && str2double(obj.Handles.BPHigh.Edit.String)>obj.Parameters.BPLow && str2double(obj.Handles.BPHigh.Edit.String)<obj.RawFrequency/2,
                obj.Parameters.BPHigh = str2double(obj.Handles.BPHigh.Edit.String);
            else
                obj.Handles.BPHigh.Edit.String = num2str(obj.Parameters.BPHigh);
            end
        end
        
        function BPLowEditCB(obj)
            if str2double(obj.Handles.BPLow.Edit.String)>0 && str2double(obj.Handles.BPLow.Edit.String)<obj.Parameters.BPHigh
                % If too large, the smooth function will take care of the
                % error
                obj.Parameters.BPLow = str2double(obj.Handles.BPLow.Edit.String);
            else
                obj.Handles.BPLow.Edit.String = num2str(obj.Parameters.BPLow);
            end
        end
        
         function BPSetCB(obj)
             obj.BPHighEditCB;
             obj.BPLowEditCB;
             if obj.Parameters.BPEnable
                 obj.Preprocess;
             end
        end
        
        % Detection
        function PowerEditCB(obj)
            if str2double(obj.Handles.Power.Edit.String)>0 && str2double(obj.Handles.Power.Edit.String)<10 
                obj.Parameters.Power = str2double(obj.Handles.Power.Edit.String);
                obj.Detect;
            else
                obj.Handles.Power.Edit.String = num2str(obj.Parameters.Power);
            end
        end
        
        function ThresholdEditCB(obj)
            if str2double(obj.Handles.Threshold.Edit.String)>0
                obj.Parameters.Threshold = str2double(obj.Handles.Threshold.Edit.String);
                obj.Handles.ThresholdLine.YData = [obj.Parameters.Threshold obj.Parameters.Threshold];
            else
                obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Threshold);
            end
        end
        
        function SmoothDetectionEditCB(obj)
            if str2double(obj.Handles.SmoothDetection.Edit.String)>0
                obj.Parameters.SmoothDetection = str2double(obj.Handles.SmoothDetection.Edit.String);
                obj.Detect;
            else
                obj.Handles.SmoothDetection.Edit.String = num2str(obj.Parameters.SmoothDetection);
            end
        end
        
        function WaveformWindowLowEditCB(obj)
            if str2double(obj.Handles.WaveformWindowLow.Edit.String)<obj.Parameters.WaveformWindowHigh
                obj.Parameters.WaveformWindowLow = str2double(obj.Handles.WaveformWindowLow.Edit.String);
            else
                obj.Handles.WaveformWindowLow.Edit.String = num2str(obj.Parameters.WaveformWindowLow);
            end
        end
        
        function WaveformWindowHighEditCB(obj)
            if str2double(obj.Handles.WaveformWindowHigh.Edit.String)>obj.Parameters.WaveformWindowLow
                obj.Parameters.WaveformWindowHigh = str2double(obj.Handles.WaveformWindowHigh.Edit.String);
            else
                obj.Handles.WaveformWindowHigh.Edit.String = num2str(obj.Parameters.WaveformWindowHigh);
            end
        end
                
        function ThresholdSetCB(obj)
            if str2double(obj.Handles.Threshold.Edit.String)>0
                obj.Parameters.Threshold = str2double(obj.Handles.Threshold.Edit.String);
                obj.Handles.ThresholdLine.YData = [obj.Parameters.Threshold obj.Parameters.Threshold];
                obj.Detect;
            else
                obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Threshold);
            end
        end
        
        function WindowLHSetCB(obj)
            obj.WaveformWindowLowEditCB;
            obj.WaveformWindowHighEditCB;
            obj.Detect;
        end
        
        function ThresholdDragCB(obj)
            if ~obj.Dragging
                obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingThresholdLine;
                obj.Figure.WindowButtonUpFcn = @(~,~)obj.ThresholdDragCB;
                obj.Dragging = true;
            else
                obj.Dragging = false;
                obj.Figure.WindowButtonMotionFcn = [];
                obj.Figure.WindowButtonUpFcn = [];
            end
        end
        
        function MovingThresholdLine(obj)
            CurrentCursor = obj.SubEnhanced.CurrentPoint;
            if CurrentCursor(1,2)>=0 && CurrentCursor(1,2)<=obj.SubEnhanced.YLim(2)
                obj.Handles.ThresholdLine.YData = [CurrentCursor(1,2) CurrentCursor(1,2)];
                obj.Handles.Threshold.Edit.String = num2str(CurrentCursor(1,2),3);
                drawnow;
            end
        end
    
        
        % Manual interventions
        function LockXCB(obj)
            if obj.Handles.LockX.Value==0
                obj.Handles.ZoomSubEnhanced.Motion = 'both';
                obj.Handles.ZoomSubHR.Motion = 'both';
                obj.Handles.ZoomSubPeaks.Motion = 'both';
                obj.Handles.ZoomSubRaw.Motion = 'both';
            elseif obj.Handles.LockX.Value==1
                obj.Handles.ZoomSubEnhanced.Motion = 'vertical';
                obj.Handles.ZoomSubHR.Motion = 'vertical';
                obj.Handles.ZoomSubPeaks.Motion = 'vertical';
                obj.Handles.ZoomSubRaw.Motion = 'vertical';
                obj.Handles.LockY.Value = 0;
            end
        end
                
        function LockYCB(obj)
            if obj.Handles.LockY.Value==0
                obj.Handles.ZoomSubEnhanced.Motion = 'both';
                obj.Handles.ZoomSubHR.Motion = 'both';
                obj.Handles.ZoomSubPeaks.Motion = 'both';
                obj.Handles.ZoomSubRaw.Motion = 'both';
            elseif obj.Handles.LockY.Value==1
                obj.Handles.ZoomSubEnhanced.Motion = 'horizontal';
                obj.Handles.ZoomSubHR.Motion = 'horizontal';
                obj.Handles.ZoomSubPeaks.Motion = 'horizontal';
                obj.Handles.ZoomSubRaw.Motion = 'horizontal';
                obj.Handles.LockX.Value = 0;
            end
        end
        
        function EnableShapesCB(obj)
            obj.DisableAll;
            if obj.Handles.EnableShapes.Value==0
                obj.Parameters.ShapesEnable = 0;
                delete(obj.Handles.ShapesBeats);
            else
                obj.Parameters.ShapesEnable = 1;
                obj.Handles.ShapesBeats = plot((obj.Times(obj.RangeShapes))', obj.Shapes','Color',[0.8 0.8 0.8],'LineWidth',1.5,'Parent',obj.SubPeaks);
                [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
                set(obj.Handles.ShapesBeats(Indx),{'Color'},repmat({obj.Colors(2,:)},numel(Indx),1))
                delete(obj.Handles.MarkersBeats)
                delete(obj.Handles.MarkersAll)
                obj.Handles.MarkersAll = plot(obj.Peaks,zeros(size(obj.Peaks)),'d','Color',[0.6 0.6 0.6],'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',[0.6 0.6 0.6]);
                obj.Handles.MarkersBeats = plot(obj.HeartBeats,zeros(size(obj.HeartBeats)),'d','Color',obj.Colors(3,:),'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',obj.Colors(3,:));
                if obj.Parameters.RPeaksEnable,
                    uistack(obj.Handles.RPeaks,'top');
                end
            end
            obj.EnableAll;
        end
        
        function RPeaksEnableCB(obj)
            obj.DisableAll;
            if obj.Handles.RPeaksEnable.Value==0
                obj.Parameters.RPeaksEnable = 0;
                if isfield(obj.Handles,'RPeaks')
                    delete(obj.Handles.RPeaks)
                end
            else
                obj.Parameters.RPeaksEnable = 1;
                [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
                if isfield(obj.Handles,'RPeaks')
                    delete(obj.Handles.RPeaks)
                end
                obj.Handles.RPeaks = plot(([obj.RPeaks(:,1) obj.RPeaks(:,1)])', ([obj.RPeaks(:,2) obj.RPeaks(:,2)])','o','Color','none','MarkerSize',10,'LineWidth',1.5,'Parent',obj.SubPeaks);
                set(obj.Handles.RPeaks(Indx),{'Color'},repmat({'k'},numel(Indx),1))
            end
            obj.EnableAll;
        end
        
        
        function AutoUpdateHRCB(obj)
             if obj.Handles.AutoUpdateHR.Value==0
                obj.Parameters.AutoUpdate = 0;
             else
                 obj.Parameters.AutoUpdate = 1;
             end
        end
        
        function SaveCB(obj)
            obj.DisableAll;
            [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
            RPeaks = obj.RPeaks(Indx,1);
            if obj.Frequency<obj.RawFrequency
                % We need to clean that signal as well
                % Remove drift
                ECGDeDrift = obj.RawValues - smoothdata(obj.RawValues,'gaussian',round(obj.Parameters.SmoothKernel*obj.RawFrequency/obj.Frequency));
                % Filter
                if obj.Parameters.BPEnable
                    Preprocessed = bandpass(ECGDeDrift,[obj.Parameters.BPLow obj.Parameters.BPHigh],obj.RawFrequency);
                    if strcmpi(obj.Parameters.Species,'Human')
                        Preprocessed = bandstop(Preprocessed,[45 55],obj.RawFrequency);
                    end
                else
                    Preprocessed = ECGDeDrift;
                end
                IndxRmv = [];
                if strcmpi(obj.Parameters.Species,'Mouse')
                    % Enhance
                    SqECG = Smooth(abs(Preprocessed).^obj.Parameters.Power,4);
                    SqECG2 = SqECG.^2;
                    
                    % Get peaks (automatic detection)
                    [~,Index,~,Height] = findpeaks(SqECG2);
                    
                    % Make a template from the "representative" peaks
                    SamplesRange = [round(obj.Parameters.WaveformWindowLow*obj.RawFrequency/obj.Frequency):round(obj.Parameters.WaveformWindowHigh*obj.RawFrequency/obj.Frequency)];
                    Index_Perc = Height>prctile(Height,70) & Height<prctile(Height,90);
                    IndexTemplates = Index(Index_Perc);
                    IndexTemplates = IndexTemplates(IndexTemplates>(abs(round(obj.Parameters.WaveformWindowLow*obj.RawFrequency/obj.Frequency)) + 1) & IndexTemplates<(Index(end)-(round(obj.Parameters.WaveformWindowHigh*obj.RawFrequency/obj.Frequency)+1)));
                    RangeTemplates = repmat(IndexTemplates,1,numel(SamplesRange)) + SamplesRange;
                    Shapes = Preprocessed(RangeTemplates);
                    Template = median(zscore(Shapes,1,2),1);
                    
                    % Remove "big" artifacts
                    RmvRange = [-5 5];
                    [~,PeakTIndex] = max(median(Shapes,1));
                    RawPeakValueHigh = 1.4*max(Shapes(:,PeakTIndex));
                    [~,PeakTIndex] = min(median(Shapes,1));
                    RawPeakValueLow = 1.5*min(Shapes(:,PeakTIndex));
                    OutIndex = find(Preprocessed>RawPeakValueHigh | Preprocessed<RawPeakValueLow);
                    if numel(OutIndex)>2
                    Art = FindContinuousRange(OutIndex);
                    % Merge events when close
                    for KOA = 2 : numel(Art(:,1))
                        if (OutIndex(Art(KOA,1))-OutIndex(Art(KOA-1,2)))<(obj.Frequency/5) % 200ms
                            Art(KOA,1) = Art(KOA-1,1);
                            Art(KOA-1,:) = NaN(1,3);
                        end
                    end
                    Art = OutIndex(Art(~isnan(Art(:,1)),[1 2]));
                    if numel(Art) == 2,
                        Art = Art';
                    end
                    IndexDuration = (Art(:,2)-Art(:,1))>(obj.RawFrequency/10);
                    Art(IndexDuration,1) = Art(IndexDuration,1)-obj.RawFrequency/20;
                    Art(IndexDuration,2) = Art(IndexDuration,2)+obj.RawFrequency/20;
                    
                    Cleaned_ECG = Preprocessed;
                    IndxRmv = [];
                    NumSamples = numel(Cleaned_ECG);
                    for K = 1 : numel(Art(:,1))
                        if Art(K,1)>3 && Art(K,2)<(NumSamples-3)
                            Cleaned_ECG(Art(K,1)-3:Art(K,2)+3) = 0;
                            IndxRmv = [IndxRmv;[Art(K,1)-3,Art(K,2)+3]];
                        end
                    end
                    Preprocessed = Cleaned_ECG;
                    end
                end
                
                if obj.Parameters.RPeaksFilter
                    RawValues = smoothdata(Preprocessed,'sgolay');
                else
                    RawValues = Preprocessed;
                end
                RPeaksIndex_S = round(RPeaks*obj.RawFrequency - obj.Parameters.Frag * obj.RawFrequency);
                tic
                Range = ceil(1+obj.RawFrequency/obj.Frequency);
                RPeaksValue = arrayfun(@(x) max(RawValues(RPeaksIndex_S(x)-Range : RPeaksIndex_S(x)+Range)),1:numel(RPeaks));
                RPeaksIndex = arrayfun(@(x) find(RawValues(RPeaksIndex_S(x)-Range : RPeaksIndex_S(x)+Range)==RPeaksValue(x)),1:numel(RPeaks),'UniformOutput',false);
                % Check if we have ties...
                IndxMultiple = find(arrayfun(@(x) numel(RPeaksIndex{x})>1,1:numel(RPeaksIndex)));
                if ~isempty(IndxMultiple),
                    for IM = 1 : numel(IndxMultiple),
                        [~,IndxKeep] = min(abs(RPeaksIndex{IndxMultiple(IM)}-Range));
                        Sh = RPeaksIndex{IndxMultiple(IM)};
                        RPeaksIndex{IndxMultiple(IM)} = Sh(IndxKeep);
                    end
                end
                RPeaksIndex = cell2mat(RPeaksIndex) - Range - 1;
                RPeaksTimes = obj.RawTimes(RPeaksIndex_S+RPeaksIndex');
            else
                RPeaksTimes = RPeaks;
            end
            % Heartbeats file
            %  HeartBeats.AddedBeats = obj.AddedBeats;
            HeartBeats.RPeaks = RPeaksTimes;
            HeartBeats.HeartBeats = obj.HeartBeats;
            HeartBeats.Artefacts = obj.Artefacts;
            HeartBeats.RemovedWindows = obj.RemovedWindows;
            save(obj.HeartBeatsFile,'-Struct','HeartBeats');
            % Logfile
            CurrLog = {datetime,getenv('username')};
            if exist(obj.LogFile,'file')
                Log = load(obj.LogFile);
                if isfield(Log,'Log')
                    Log.Log = [Log.Log; CurrLog];
                else
                    Log.Log = [CurrLog]; % Legacy
                end
            else
                Log.Log = CurrLog;
            end
            Log.Parameters = obj.Parameters;
            save(obj.LogFile,'-Struct','Log');
            obj.EnableAll;
        end
        
        function ExitCB(obj)
            close(obj.Figure)
        end
        
        function AutoLims(obj)
            obj.SubEnhanced.XLimMode = 'auto';
            obj.SubHR.XLimMode = 'auto';
            obj.SubPeaks.XLimMode = 'auto';
            obj.SubRaw.XLimMode = 'auto';
            obj.SubEnhanced.YLimMode = 'auto';
            obj.SubHR.YLimMode = 'auto';
            obj.SubPeaks.YLimMode = 'auto';
            obj.SubRaw.YLimMode = 'auto';
        end
        
        function EvaluateWindow(obj)
            drawnow;
            if obj.SubHR.XLim(1)<0
                obj.SubHR.XLim(1) = 0;
            elseif obj.SubHR.XLim(2)>obj.Times(end)
                obj.SubHR.XLim(2) = obj.Times(end);
            end
            if obj.Handles.SliderLine.XData(1)<obj.SubHR.XLim(1) || obj.Handles.SliderLine.XData(1)>obj.SubHR.XLim(2),
                obj.Handles.SliderLine.XData = [1 1] * obj.SubHR.XLim(1) + 0.5*diff(obj.SubHR.XLim);
            end
        end
        
        function SliderCB(obj)
            if ~obj.Dragging
                if ~isempty(obj.Times)
                    obj.Dragging = true;
                    obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingSlider;
                    obj.Figure.WindowButtonUpFcn = @(~,~)obj.SliderCB;
                end
            else
                obj.Dragging = false;
                obj.Figure.WindowButtonMotionFcn = [];
                obj.Figure.WindowButtonUpFcn = [];
            end
        end
        
        function MovingSlider(obj)
            CurrentCursor = obj.Slider.CurrentPoint;
            if (CurrentCursor(1) + 0.5*diff(obj.SubHR.XLim))<=obj.Times(end) && (CurrentCursor(1) - 0.5*diff(obj.SubHR.XLim))>=obj.Times(1),
                obj.SubHR.XLim = [CurrentCursor(1)-0.5*diff(obj.SubHR.XLim) CurrentCursor(1)+0.5*diff(obj.SubHR.XLim)];
                obj.Handles.SliderLine.XData = [CurrentCursor(1) CurrentCursor(1)];
            elseif (CurrentCursor(1) + 0.5*diff(obj.SubHR.XLim))>obj.Times(end)
                obj.SubHR.XLim = [obj.Times(end)-diff(obj.SubHR.XLim) obj.Times(end)];
                if CurrentCursor(1) > obj.Times(end)
                    obj.Handles.SliderLine.XData = [obj.Times(end) obj.Times(end)];
                else
                    obj.Handles.SliderLine.XData = [CurrentCursor(1) CurrentCursor(1)];
                end
            else
                obj.SubHR.XLim = [obj.Times(1) obj.Times(1)+diff(obj.SubHR.XLim)];
                if CurrentCursor(1) < obj.Times(1)
                    obj.Handles.SliderLine.XData = [obj.Times(1) obj.Times(1)];
                else
                    obj.Handles.SliderLine.XData = [CurrentCursor(1) CurrentCursor(1)];
                end
            end
            drawnow
        end
            
        function SelectBeat(obj)
            % Retrieve X coordinate
            Clicked = obj.SubPeaks.CurrentPoint;
            % Find closer peak
            [~,IndexPoint] = min(abs(Clicked(1) - obj.Peaks));
            ClickedPeak = obj.Peaks(IndexPoint);
            % Check if selected or not
            if any(obj.HeartBeats==ClickedPeak)
                IndxD = obj.HeartBeats==ClickedPeak;
                obj.Handles.MarkersBeats.XData(IndxD) = [];
                obj.Handles.MarkersBeats.YData(IndxD) = [];
                if obj.Parameters.ShapesEnable
                    obj.Handles.ShapesBeats(IndexPoint).Color = [0.8 0.8 0.8];
                end
                if obj.Parameters.RPeaksEnable
                    obj.Handles.RPeaks(IndexPoint).Color = 'none';
                end
                obj.HeartBeats(IndxD) = [];
                if obj.Parameters.AutoUpdate
                    obj.DisableAll;
                    obj.ProcessHeartRate;
                end
            else
                obj.HeartBeats = sort([obj.HeartBeats,ClickedPeak]);
                obj.Handles.MarkersBeats.XData = sort([obj.Handles.MarkersBeats.XData,ClickedPeak]);
                obj.Handles.MarkersBeats.YData = [obj.Handles.MarkersBeats.YData,0];
                if obj.Parameters.ShapesEnable
                    obj.Handles.ShapesBeats(IndexPoint).Color = obj.Colors(2,:);
                end
                if obj.Parameters.RPeaksEnable
                    obj.Handles.RPeaks(IndexPoint).Color = 'k';
                end
                if obj.Parameters.AutoUpdate
                    obj.DisableAll;
                    obj.ProcessHeartRate;
                end
            end
        end
    
        function AddSingleBeatCB(obj)
            NewPeak = ginput(1);
            % Find closest sample
            [~,IndexPoint] = min(abs(NewPeak(1) - obj.Times));
            NewPeak = obj.Times(IndexPoint);
            if ~any(NewPeak == obj.Peaks)
                obj.HeartBeats = sort([obj.HeartBeats,NewPeak]);
                [obj.Peaks,IndxSort] = sort([obj.Peaks,NewPeak]);
                % Add shape
                SamplesRange = [obj.Parameters.WaveformWindowLow:obj.Parameters.WaveformWindowHigh];
                obj.RangeShapes = [obj.RangeShapes; IndexPoint + SamplesRange];
                obj.Shapes = [obj.Shapes; (obj.Preprocessed(IndexPoint + SamplesRange))'];
                if obj.Parameters.ShapesEnable
                    Line = plot(obj.Times(obj.RangeShapes(end,:)), obj.Shapes(end,:),'Color',obj.Colors(2,:),'LineWidth',1.5,'Parent',obj.SubPeaks);
                end
                % Update markers (replotting is actually faster than bringing
                % on top....)
                delete(obj.Handles.MarkersBeats)
                delete(obj.Handles.MarkersAll)
                obj.Handles.MarkersAll = plot(obj.Peaks,zeros(size(obj.Peaks)),'d','Color',[0.6 0.6 0.6],'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',[0.6 0.6 0.6]);
                obj.Handles.MarkersBeats = plot(obj.HeartBeats,zeros(size(obj.HeartBeats)),'d','Color',obj.Colors(3,:),'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',obj.Colors(3,:));
                if obj.Parameters.ShapesEnable
                    obj.Handles.ShapesBeats = [obj.Handles.ShapesBeats;Line];
                     obj.Handles.ShapesBeats = obj.Handles.ShapesBeats(IndxSort);
                    %                 obj.Handles.ShapesBeats = [obj.Handles.ShapesBeats(1:IndxSort(end)-1);Line;obj.Handles.ShapesBeats(IndxSort(end):end)];
                    %                 obj.Handles.ShapesBeats = [];
                    %                 obj.Handles.ShapesBeats = Temp;
%                     obj.Handles.ShapesBeats = plot((obj.Times(obj.RangeShapes))', obj.Shapes','Color',[0.8 0.8 0.8],'LineWidth',1.5,'Parent',obj.SubPeaks);
%                     [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
%                     set(obj.Handles.ShapesBeats(Indx),{'Color'},repmat({obj.Colors(2,:)},numel(Indx),1))
                end
%                 obj.AddedBeats = [obj.AddedBeats;NewPeak];
                obj.RangeShapes = obj.RangeShapes(IndxSort,:);
                obj.Shapes = obj.Shapes(IndxSort,:);
                obj.ProcessHeartRate;
            end
        end
                
        function AddRangeCB(obj)
            D = drawrectangle(obj.SubPeaks);
            NewWindow = [D.Position(1),D.Position(1)+D.Position(3)];
            delete(D)
            obj.RemovedWindows = sort([obj.RemovedWindows; NewWindow]);

            % Find and remove potential overlaps (ms accuracy)
            IndxRmv = round(obj.RemovedWindows*obj.Frequency);
            Break = false;
            if numel(IndxRmv(:,1))>1
                while ~Break
                    Break = true;
                    Reloop = false;
                    % Loop through the ranges
                    for R = 1 : numel(IndxRmv(:,1)),
                        for S = 1 : numel(IndxRmv(:,1)),
                            if S~=R,
                                if ~Reloop
                                    % Find intersections
                                    Intrsct = intersect(IndxRmv(R,1):IndxRmv(R,2),IndxRmv(S,1):IndxRmv(S,2));
                                    if ~isempty(Intrsct),
                                        % Extend ranges
                                        Min = min([IndxRmv(R,1) IndxRmv(S,1)]);
                                        IndxRmv(R,1) = Min;
                                        IndxRmv(S,1) = Min;
                                        Min = min([obj.RemovedWindows(R,1) obj.RemovedWindows(S,1)]);
                                        obj.RemovedWindows(R,1) = Min;
                                        obj.RemovedWindows(S,1) = Min;
                                        Max = max([IndxRmv(R,2) IndxRmv(S,2)]);
                                        IndxRmv(R,2) = Max;
                                        IndxRmv(S,2) = Max;
                                        Max = max([obj.RemovedWindows(R,2) obj.RemovedWindows(S,2)]);
                                        obj.RemovedWindows(R,2) = Max;
                                        obj.RemovedWindows(S,2) = Max;
                                        Break = false;
                                        obj.RemovedWindows = unique(obj.RemovedWindows,'rows');
                                        IndxRmv = unique(IndxRmv,'rows');
                                        Reloop = true;
                                    end
                                end
                            end
                        end
                    end
                end
            end
            obj.RemovedWindows = sort(unique(obj.RemovedWindows,'rows'));
            
            Subs = {'SubPeaks','SubHR','SubEnhanced'};
            for S = 1 : numel(Subs),
                delete(obj.Handles.FillRemovedWindows.(Subs{S}))
                obj.Handles.FillRemovedWindows.(Subs{S}) = arrayfun(@(x) fill([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)], [ obj.Handles.Min.(Subs{S})  obj.Handles.Min.(Subs{S})  obj.Handles.Max.(Subs{S})  obj.Handles.Max.(Subs{S})],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.(Subs{S}),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.RemovedWindows(:,1)));
                uistack(obj.Handles.FillRemovedWindows.(Subs{S}),'bottom')
            end
        end
        
        function SelectWindow(obj,src,~)
            Subs = {'SubPeaks','SubHR','SubEnhanced'};
            if obj.Selected == str2double(src.Tag),
                obj.Selected = [];
                Colors = repmat({[0.85 0.85 0.9]},numel(obj.RemovedWindows(:,1)),1);
                LineColors = repmat({[1 1 1]},numel(obj.RemovedWindows(:,1)),1);
                for S = 1 : numel(Subs),
                    set(obj.Handles.FillRemovedWindows.(Subs{S}),{'FaceColor'},Colors)
                    set(obj.Handles.FillRemovedWindows.(Subs{S}),{'EdgeColor'},LineColors)
                end
            else
                obj.Selected = str2double(src.Tag);
                Colors = repmat({[0.85 0.85 0.9]},numel(obj.RemovedWindows(:,1)),1);
                LineColors = repmat({[1 1 1]},numel(obj.RemovedWindows(:,1)),1);
                Colors(obj.Selected,:) = {[0.5 0.85 0.94]};
                LineColors(obj.Selected,:) = {[0 0 0]};
                for S = 1 : numel(Subs),
                    set(obj.Handles.FillRemovedWindows.(Subs{S}),{'FaceColor'},Colors)
                    set(obj.Handles.FillRemovedWindows.(Subs{S}),{'EdgeColor'},LineColors)
                end
            end
        end
        
        
        function DeleteRangeCB(obj)
            Subs = {'SubPeaks','SubHR','SubEnhanced'};
            if ~isempty(obj.Selected),
                obj.RemovedWindows(obj.Selected,:) = [];
                for S = 1 : numel(Subs),
                    delete(obj.Handles.FillRemovedWindows.(Subs{S}))
                    obj.Handles.FillRemovedWindows.(Subs{S}) = arrayfun(@(x) fill([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)], [ obj.Handles.Min.(Subs{S})  obj.Handles.Min.(Subs{S})  obj.Handles.Max.(Subs{S})  obj.Handles.Max.(Subs{S})],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.(Subs{S}),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.RemovedWindows(:,1)));
                    uistack(obj.Handles.FillRemovedWindows.(Subs{S}),'bottom')
                end
            end
            obj.Selected = [];
        end
        
        
        % Heart rate
        function SlidingWindowSizeEditCB(obj)
             if str2double(obj.Handles.SlidingWindowSize.Edit.String)>0,
                obj.Parameters.SlidingWindowSize = str2double(obj.Handles.SlidingWindowSize.Edit.String);
                obj.ProcessHeartRate;
                obj.SubHR.YLimMode = 'auto';
            else
                obj.Handles.SlidingWindowSize.Edit.String = num2str(obj.Parameters.SlidingWindowSize);
            end
        end
                
        function BPMCB(obj)
            if  obj.Handles.BPM.Value ==1,
                obj.Parameters.Unit = 'BPM';
                obj.Handles.Hz.Value = 0;drawnow
                obj.DisableAll;
                obj.SubHR.YLabel.String = 'Heart rate (BPM)';
                obj.SubHR.Children(1).YData = obj.SubHR.Children(1).YData*60;
            else
                 obj.Handles.Hz.Value = 1;drawnow
                 obj.DisableAll;
                 obj.Parameters.Unit = 'Hz';
                 obj.SubHR.YLabel.String = 'Heart rate (Hz)';
                 obj.SubHR.Children(1).YData = obj.SubHR.Children(1).YData/60;
            end 
            obj.SubHR.YLimMode = 'auto';
            drawnow
            obj.EnableAll;
        end
        
        function HzCB(obj)
            obj.DisableAll;
            if  obj.Handles.Hz.Value ==1,
                obj.Handles.BPM.Value = 0;drawnow
                obj.DisableAll;
                obj.Parameters.Unit = 'Hz';
                obj.SubHR.YLabel.String = 'Heart rate (Hz)';
                obj.SubHR.Children(1).YData = obj.SubHR.Children(1).YData/60;
            else
                 obj.Handles.BPM.Value = 1;drawnow
                 obj.DisableAll;
                 obj.Parameters.Unit = 'BPM';
                 obj.SubHR.YLabel.String = 'Heart rate (BPM)';
                 obj.SubHR.Children(1).YData = obj.SubHR.Children(1).YData*60;
            end
            drawnow
            obj.EnableAll;
        end
        
        % Processing functions
        
        function Preprocess(obj,varargin)
            if ~isempty(obj.Previous)
                Reprocess = false;
                % Check whether anything is different from last call
                % File
                if strcmpi(obj.Previous.File,obj.RawFile),
                    % Bandpass
                    if ~(obj.Parameters.BPEnable == obj.Previous.BPEnable),
                        Reprocess = true;
                    end
                    if obj.Parameters.BPEnable,
                        if ~(obj.Parameters.BPHigh == obj.Previous.BPHigh),
                            Reprocess = true;
                        end
                        if ~(obj.Parameters.BPLow == obj.Previous.BPLow),
                            Reprocess = true;
                        end
                    end
                    % Smoothing
                    if ~(obj.Parameters.SmoothKernel == obj.Previous.SmoothKernel),
                        Reprocess = true;
                    end
                else
                    Reprocess = true;
                end
            else
                Reprocess = true;
            end
            if Reprocess | ~isempty(varargin),
                % Make sure interactions are disabled during processing
                obj.DisableAll;
                % Decimate if above 1000Hz (enough for processing)
                if  obj.RawFrequency>1000,
                    ECG_Raw = decimate(obj.RawValues,floor(obj.RawFrequency/1000));
                    obj.Times = downsample(obj.RawTimes,floor(obj.RawFrequency/1000));
                    obj.Frequency = 1000;
                else
                    obj.Times = obj.RawTimes;
                    ECG_Raw = obj.RawValues;
                    obj.Frequency = obj.RawFrequency;
                end
                
                % Remove drift
                ECGDeDrift = ECG_Raw - smoothdata(ECG_Raw,'gaussian',obj.Parameters.SmoothKernel);
                
                % Filter
                if obj.Parameters.BPEnable,
                    obj.Preprocessed = bandpass(ECGDeDrift,[obj.Parameters.BPLow obj.Parameters.BPHigh],obj.Frequency);
                    if strcmpi(obj.Parameters.Species,'Human'),
                        obj.Preprocessed = bandstop(ECGDeDrift,[45 55],obj.Frequency);
                    end
                else
                    obj.Preprocessed = ECGDeDrift;
                end
                IndxRmv = [];
                if strcmpi(obj.Parameters.Species,'Mouse'),
                    % Enhance
                    SqECG = Smooth(abs(obj.Preprocessed).^obj.Parameters.Power,4);
                    SqECG2 = SqECG.^2;
                    
                    % Get peaks (automatic detection)
                    [~,Index,~,Height] = findpeaks(SqECG2);
                    
                    % Make a template from the "representative" peaks
                    SamplesRange = [obj.Parameters.WaveformWindowLow:obj.Parameters.WaveformWindowHigh];
                    Index_Perc = Height>prctile(Height,70) & Height<prctile(Height,90);
                    IndexTemplates = Index(Index_Perc);
                    IndexTemplates = IndexTemplates(IndexTemplates>(abs(obj.Parameters.WaveformWindowLow) + 1) & IndexTemplates<(Index(end)-(obj.Parameters.WaveformWindowHigh+1)));
                    RangeTemplates = repmat(IndexTemplates,1,numel(SamplesRange)) + SamplesRange;
                    Shapes = obj.Preprocessed(RangeTemplates);
                    Template = median(zscore(Shapes,1,2),1);
                    
                    % Remove "big" artifacts
                    RmvRange = [-5 5];
%                     [~,PeakTIndex] = max(median(Shapes,1));
%                     RawPeakValueHigh = 1.4*max(Shapes(:,PeakTIndex));
%                     [~,PeakTIndex] = min(median(Shapes,1));
%                     RawPeakValueLow = 1.5*min(Shapes(:,PeakTIndex));
                    RawPeakValueHigh = 2*prctile(Shapes, 0.9,1);
                    RawPeakValueLow = 2*prctile(-Shapes, 0.9,1);
                    OutIndex = find(obj.Preprocessed>RawPeakValueHigh | obj.Preprocessed<RawPeakValueLow);
                    if numel(OutIndex)>2,
                    Art = FindContinuousRange(OutIndex);
                    % Merge events when close
                    for KOA = 2 : numel(Art(:,1))
                        if (OutIndex(Art(KOA,1))-OutIndex(Art(KOA-1,2)))<(obj.Frequency/5), % 200ms
                            Art(KOA,1) = Art(KOA-1,1);
                            Art(KOA-1,:) = NaN(1,3);
                        end
                    end
                    Art = OutIndex(Art(~isnan(Art(:,1)),[1 2]));
                    if numel(Art) == 2,
                        Art = Art';
                    end
                    IndexDuration = (Art(:,2)-Art(:,1))>(obj.Frequency/10);
                    Art(IndexDuration,1) = Art(IndexDuration,1)-obj.Frequency/20;
                    Art(IndexDuration,2) = Art(IndexDuration,2)+obj.Frequency/20;
                    
                    Cleaned_ECG = obj.Preprocessed;
                    IndxRmv = [];
                    NumSamples = numel(Cleaned_ECG);
                    for K = 1 : numel(Art(:,1)),
                        if Art(K,1)>3 && Art(K,2)<(NumSamples-3),
                            Cleaned_ECG(Art(K,1)-3:Art(K,2)+3) = 0;
                            IndxRmv = [IndxRmv;[Art(K,1)-3,Art(K,2)+3]];
                        end
                    end
                    obj.IndxRmv = IndxRmv;
                    obj.Preprocessed = Cleaned_ECG;
                    end
                end
                
                % Plot
                delete(obj.SubRaw.Children)
                plot(obj.Times,ECG_Raw,'LineWidth',1,'Parent',obj.SubRaw,'Color',obj.Colors(1,:));
                hold(obj.SubRaw,'on')
                plot(obj.Times,obj.Preprocessed,'LineWidth',1,'Parent',obj.SubRaw,'Color',obj.Colors(2,:));
                obj.Artefacts = obj.Times(IndxRmv);
                if ~isempty(IndxRmv),
                    Max = max([obj.Preprocessed;ECG_Raw]);
                    Min = min([obj.Preprocessed;ECG_Raw]);
                    % Plot ranges discarded because of artefacts
                    FillArtefact = arrayfun(@(x) fill(obj.Times([IndxRmv(x,1) IndxRmv(x,2) IndxRmv(x,2) IndxRmv(x,1)]), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor','none','Parent',obj.SubRaw),1:numel(IndxRmv(:,1)));
                    uistack(FillArtefact,'bottom')
                end
                if strcmpi(obj.Parameters.Species,'Mouse'),
                    % Set YLim rather for the cleaned signal
                    Max = max(obj.Preprocessed);
                    Min = min(obj.Preprocessed);
                    obj.SubRaw.YLim = [Min - 0.1*(Max-Min) Max + 0.1*(Max-Min)];
                end
                obj.SubplotVisual;
                XL = obj.Times([1 end]);
                obj.AutoLims;
                obj.SubEnhanced.XLim = XL;
                obj.SubHR.XLim = XL;
                obj.SubPeaks.XLim = XL;
                obj.SubRaw.XLim = XL;
                obj.Slider.XLimMode = 'manual';
                obj.Slider.XLim = XL;
                obj.Detect('Pre');
            else
                obj.Detect;
            end
        end
        
        function Detect(obj,varargin)
            if ~isempty(varargin),
                Reprocess = true;
            else
                if ~isempty(obj.Previous)
                    Reprocess = false;
                    % Check whether anything is different from last call
                    % File
                    if strcmpi(obj.Previous.File,obj.RawFile),
                        % Power
                        if ~(obj.Parameters.Power == obj.Previous.Power),
                            Reprocess = true;
                        end
                        % Threshold
                        if ~(obj.Parameters.Threshold == obj.Previous.Threshold),
                            Reprocess = true;
                        end
                        % SmoothDetection
                        if ~(obj.Parameters.SmoothDetection == obj.Previous.SmoothDetection),
                            Reprocess = true;
                        end
                        % WaveformWindowLow
                        if ~(obj.Parameters.WaveformWindowLow == obj.Previous.WaveformWindowLow),
                            Reprocess = true;
                        end
                        % WaveformWindowHigh
                        if ~(obj.Parameters.WaveformWindowHigh == obj.Previous.WaveformWindowHigh),
                            Reprocess = true;
                        end
                    end
                else
                    Reprocess = true;
                end
            end
            if Reprocess,
                % Make sure interactions are disabled during processing
                obj.DisableAll;
                
                % Transform values to get the beats more separate from the noise
                SqECG = Smooth(abs(obj.Preprocessed).^obj.Parameters.Power,obj.Parameters.SmoothDetection);
                SqECG2 = SqECG.^2;
              
                % Get peaks (automatic detection)
                [~,Index,~,Height] = findpeaks(SqECG2);
                PeaksIndex = Index(Height>obj.Parameters.Threshold);
                SamplesRange = [obj.Parameters.WaveformWindowLow:obj.Parameters.WaveformWindowHigh];
                Index_Perc = Height>prctile(Height,70) & Height<prctile(Height,90);
                IndexTemplates = Index(Index_Perc);
                IndexTemplates = IndexTemplates(IndexTemplates>(abs(obj.Parameters.WaveformWindowLow) + 1) & IndexTemplates<(Index(end)-(obj.Parameters.WaveformWindowHigh+1)));
                RangeTemplates = repmat(IndexTemplates,1,numel(SamplesRange)) + SamplesRange;
                
                Shapes = obj.Preprocessed(RangeTemplates);
                obj.Template = median(zscore(Shapes,1,2),1);
                HeightOr = Height;
                Height = Height(Height>obj.Parameters.Threshold);
                if isempty(PeaksIndex),
                    Answer = questdlg(['The threshold is too high to extract peaks. Do you wish to put it back into range?' newline '(It will still need adjustments)'],'Please choose...','Yes','No','Yes');
                    waitfor(Answer)
                    if strcmpi(Answer,'Yes')
                        % Use the intermediate value
                        obj.Parameters.Threshold = 0.5*(max(HeightOr)+min(HeightOr));
                        obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Threshold,3);
                        [~,Index,~,Height] = findpeaks(SqECG2);
                        PeaksIndex = Index(Height>obj.Parameters.Threshold);
                        SamplesRange = [obj.Parameters.WaveformWindowLow:obj.Parameters.WaveformWindowHigh];
                        Index_Perc = Height>prctile(Height,70) & Height<prctile(Height,90);
                        IndexTemplates = Index(Index_Perc);
                        IndexTemplates = IndexTemplates(IndexTemplates>(abs(obj.Parameters.WaveformWindowLow) + 1) & IndexTemplates<(Index(end)-(obj.Parameters.WaveformWindowHigh+1)));
                        RangeTemplates = repmat(IndexTemplates,1,numel(SamplesRange)) + SamplesRange;
                        Shapes = obj.Preprocessed(RangeTemplates);
                        obj.Template = median(zscore(Shapes,1,2),1);
                    else
                        obj.EnableAll;
                        return
                    end
                end
                PeaksIndex(PeaksIndex<=abs(obj.Parameters.WaveformWindowLow) | PeaksIndex>=(numel(obj.Preprocessed)-obj.Parameters.WaveformWindowHigh)) = [];
                if numel(PeaksIndex) < 2,
                    Answer = questdlg(['The threshold is too high to extract peaks. Do you wish to put it back into range?' newline '(It will still need adjustments)'],'Please choose...','Yes','No','Yes');
                    waitfor(Answer)
                    if strcmpi(Answer,'Yes')
                        % Use the intermediate value
                        obj.Parameters.Threshold = prctile(HeightOr,20);
                        obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Threshold,3);
                        [~,Index,~,Height] = findpeaks(SqECG2);
                        PeaksIndex = Index(Height>obj.Parameters.Threshold);
                        SamplesRange = [obj.Parameters.WaveformWindowLow:obj.Parameters.WaveformWindowHigh];
                        Index_Perc = Height>prctile(Height,70) & Height<prctile(Height,90);
                        IndexTemplates = Index(Index_Perc);
                        IndexTemplates = IndexTemplates(IndexTemplates>(abs(obj.Parameters.WaveformWindowLow) + 1) & IndexTemplates<(Index(end)-(obj.Parameters.WaveformWindowHigh+1)));
                        RangeTemplates = repmat(IndexTemplates,1,numel(SamplesRange)) + SamplesRange;
                        Shapes = obj.Preprocessed(RangeTemplates);
                        obj.Template = median(zscore(Shapes,1,2),1);
                    else
                        obj.EnableAll;
                        return
                    end
                end
                PeaksIndex(PeaksIndex<=abs(obj.Parameters.WaveformWindowLow) | PeaksIndex>=(numel(obj.Preprocessed)-obj.Parameters.WaveformWindowHigh)) = [];
                obj.RangeShapes = repmat(PeaksIndex,1,numel(SamplesRange)) + SamplesRange;
                obj.Shapes = obj.Preprocessed(obj.RangeShapes);
                obj.Peaks = obj.Times(PeaksIndex);             
                XcorrAll = (arrayfun(@(x) max(xcorr(obj.Template,zscore(obj.Shapes(x,:),1,2))),1:numel(obj.Shapes(:,1))));
                obj.MaxCorr = max(XcorrAll);
                
                % Get RPeak position in template
                [~,RPeak_Template] = max(obj.Template);
                
                % Get positions for each peak
                % (look for the maximum around estimated location)
                RPeaksValue = arrayfun(@(x) max(obj.Shapes(x,RPeak_Template-obj.Parameters.RPeakRange:RPeak_Template+obj.Parameters.RPeakRange)),1:numel(obj.Shapes(:,1)));
                RPeaksIndex = arrayfun(@(x) find(obj.Shapes(x,RPeak_Template-obj.Parameters.RPeakRange:RPeak_Template+obj.Parameters.RPeakRange)==RPeaksValue(x)),1:numel(obj.Shapes(:,1)),'UniformOutput',false);
                % Check if we have ties...
                IndxMultiple = find(arrayfun(@(x) numel(RPeaksIndex{x})>1,1:numel(RPeaksIndex)));
                if ~isempty(IndxMultiple),
                   for IM = 1 : numel(IndxMultiple),
                       [~,IndxKeep] = min(abs(RPeaksIndex{IndxMultiple(IM)}-RPeak_Template));
                       RPeaksIndex{IndxMultiple(IM)} = IndxKeep;
                   end
                end
                RPeaksIndex = cell2mat(RPeaksIndex)+ obj.Parameters.WaveformWindowLow + RPeak_Template - obj.Parameters.RPeakRange - 2;
                RPeaksTimes = obj.Times(PeaksIndex+RPeaksIndex');
                obj.RPeaks = [RPeaksTimes',RPeaksValue'];
                % If we are loading a previous file...
                if ~(obj.ReloadMode || obj.PartialReloadMode)
                    obj.HeartBeats = obj.Peaks; % For initialization
                else
                    obj.ReloadMode = false;
                    obj.PartialReloadMode = false;
                end
                delete(obj.SubEnhanced.Children)
                plot(obj.Times,SqECG2,'LineWidth',1,'Parent',obj.SubEnhanced,'Color',obj.Colors(2,:));
                hold(obj.SubEnhanced,'on')
                MaxT = max(SqECG2);
                MinT = min(SqECG2);
                Min = MinT - 0.1*(MaxT-MinT);
                Max = MaxT + 0.1*(MaxT-MinT);
                obj.Handles.Min.SubEnhanced = Min;
                obj.Handles.Max.SubEnhanced = Max;
                if ~isempty(obj.Artefacts)||~isempty(obj.RemovedWindows),
                    if ~isempty(obj.Artefacts),
                        % Plot ranges discarded because of artefacts
                        FillArtefact = arrayfun(@(x) fill(([obj.Artefacts(x,1) obj.Artefacts(x,2) obj.Artefacts(x,2) obj.Artefacts(x,1)]), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor','none','Parent',obj.SubEnhanced),1:numel(obj.Artefacts(:,1)));
                        uistack(FillArtefact,'bottom')
                    end
                    if ~isempty(obj.RemovedWindows),
                        % Plot ranges discarded because of artefacts
                        obj.Handles.FillRemovedWindows.SubEnhanced = arrayfun(@(x) fill(([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)]), [Min Min Max Max],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.SubEnhanced,'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.RemovedWindows(:,1)));
                        uistack(obj.Handles.FillRemovedWindows.SubEnhanced,'bottom')
                    else
                        obj.Handles.FillRemovedWindows.SubEnhanced = [];
                        obj.Handles.FillRemovedWindows.SubPeaks = [];
                        obj.Handles.FillRemovedWindows.SubHR = [];
                    end
                else
                    obj.Handles.FillRemovedWindows.SubEnhanced = [];
                    obj.Handles.FillRemovedWindows.SubPeaks = [];
                    obj.Handles.FillRemovedWindows.SubHR = [];
                end
                obj.Handles.ThresholdLine = plot(obj.Times([1 end]),[obj.Parameters.Threshold obj.Parameters.Threshold],'LineWidth',3,'Parent',obj.SubEnhanced,'ButtonDownFcn',@(~,~)obj.ThresholdDragCB,'Color',obj.Colors(1,:));
                delete(obj.SubPeaks.Children)
                plot(obj.Times,obj.Preprocessed,'k','LineWidth',1,'Parent',obj.SubPeaks);
                hold(obj.SubPeaks,'on')
                MaxT = max(obj.Preprocessed);
                MinT = min(obj.Preprocessed);
                Min = MinT - 0.1*(MaxT-MinT);
                Max = MaxT + 0.1*(MaxT-MinT);
                obj.Handles.Min.SubPeaks = Min;
                obj.Handles.Max.SubPeaks = Max;
                if ~isempty(obj.Artefacts)||~isempty(obj.RemovedWindows),
                    if ~isempty(obj.Artefacts),
                        % Plot ranges discarded because of artefacts
                        FillArtefact = arrayfun(@(x) fill(([obj.Artefacts(x,1) obj.Artefacts(x,2) obj.Artefacts(x,2) obj.Artefacts(x,1)]), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor','none','Parent',obj.SubPeaks),1:numel(obj.Artefacts(:,1))); 
                        uistack(FillArtefact,'bottom')
                    end
                    if ~isempty(obj.RemovedWindows),
                        % Plot ranges discarded because of artefacts
                        obj.Handles.FillRemovedWindows.SubPeaks = arrayfun(@(x) fill(([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)]), [Min Min Max Max],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.SubPeaks,'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.RemovedWindows(:,1)));
                        uistack(obj.Handles.FillRemovedWindows.SubPeaks,'bottom')
                    end
                end
                if obj.Parameters.ShapesEnable
                    obj.Handles.ShapesBeats = plot((obj.Times(obj.RangeShapes))', obj.Shapes','Color',[0.8 0.8 0.8],'LineWidth',1.5,'Parent',obj.SubPeaks);
                    [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
                    set(obj.Handles.ShapesBeats(Indx),{'Color'},repmat({obj.Colors(2,:)},numel(Indx),1))
                end
                if obj.Parameters.RPeaksEnable,
                    obj.Handles.RPeaks = plot(([obj.RPeaks(:,1) obj.RPeaks(:,1)])', ([obj.RPeaks(:,2) obj.RPeaks(:,2)])','o','Color','none','MarkerSize',10,'LineWidth',1.5,'Parent',obj.SubPeaks);
                    [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
                    set(obj.Handles.RPeaks(Indx),{'Color'},repmat({'k'},numel(Indx),1))
                end
                obj.Handles.MarkersAll = plot(obj.Peaks,zeros(size(obj.Peaks)),'d','Color',[0.6 0.6 0.6],'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',[0.6 0.6 0.6]);
                obj.Handles.MarkersBeats = plot(obj.HeartBeats,zeros(size(obj.HeartBeats)),'d','Color',obj.Colors(3,:),'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',obj.Colors(3,:));
                obj.SubplotVisual;
                
                obj.Previous = obj.Parameters;
                obj.Previous.File = obj.RawFile;
                if ~isempty(obj.HeartBeats),
                    obj.ProcessHeartRate;
                else
                    delete(obj.SubHR.Children)
                    obj.SubplotVisual;
                    obj.EnableAll;
                end
            else
                obj.EnableAll;
            end
        end
        

        function ProcessHeartRate(obj)
            % Make sure interactions are disabled during processing
            obj.DisableAll;
            % The first values (before one window width) should be NaN
            FirstIndex = find(obj.HeartBeats>(obj.Parameters.SlidingWindowSize),1,'first');
            obj.HeartRate = NaN(size(obj.HeartBeats));
            Previous = 1;
            % Fast sliding window processing
            for K = FirstIndex:length(obj.HeartBeats),
                % Find window boundaries
                In_Interval = FindInInterval(obj.HeartBeats,[obj.HeartBeats(K)-obj.Parameters.SlidingWindowSize obj.HeartBeats(K)],Previous);
                % Memorize lower boundary to speed up next search
                Previous = In_Interval(1);
                % Compute mean: diff(In_Interval) is the number of events, divided
                % by adjusted window size
                if diff(obj.HeartBeats(In_Interval))>(obj.Parameters.SlidingWindowSize/2),
                    obj.HeartRate(K) = (diff(In_Interval))/(diff(obj.HeartBeats(In_Interval)));
                else
                    obj.HeartRate(K) = diff(In_Interval)/(obj.Parameters.SlidingWindowSize);
                end
            end
            hold(obj.SubHR,'on')
            delete(obj.SubHR.Children)
            if strcmpi(obj.Parameters.Unit,'BPM'),
                plot(obj.HeartBeats,60*obj.HeartRate,'LineWidth',1,'Color',obj.Colors(2,:),'Parent',obj.SubHR)
                obj.SubHR.YLabel.String = 'Heart rate (BPM)';
                Factor = 60;
            else
                plot(obj.HeartBeats,obj.HeartRate,'LineWidth',1,'Color',obj.Colors(2,:),'Parent',obj.SubHR)
                obj.SubHR.YLabel.String = 'Heart rate (Hz)';
                Factor = 1;
            end
            MaxT = Factor*max(obj.HeartRate);
            MinT = Factor*min(obj.HeartRate);
            Min = MinT - 0.1*(MaxT-MinT);
            Max = MaxT + 0.1*(MaxT-MinT);
            obj.Handles.Min.SubHR = Min;
            obj.Handles.Max.SubHR = Max;
            if ~isempty(obj.Artefacts)||~isempty(obj.RemovedWindows),
                if ~isempty(obj.Artefacts),
                    % Plot ranges discarded because of artefacts
                    FillArtefact = arrayfun(@(x) fill(([obj.Artefacts(x,1) obj.Artefacts(x,2) obj.Artefacts(x,2) obj.Artefacts(x,1)]), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor','none','Parent',obj.SubHR),1:numel(obj.Artefacts(:,1)));
                    uistack(FillArtefact,'bottom')
                end
                if ~isempty(obj.RemovedWindows),
                    % Plot ranges discarded because of artefacts
                    obj.Handles.FillRemovedWindows.SubHR = arrayfun(@(x) fill([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)], [Min Min Max Max],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.SubHR,'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.RemovedWindows(:,1))); 
                    uistack(obj.Handles.FillRemovedWindows.SubHR,'bottom')
                end
            end
            obj.SubplotVisual;
            obj.EnableAll;
            obj.Figure.KeyPressFcn = {@(Src,Key)obj.KeyPressCB(Src,Key)};
        end
        
        
        function ProcessCB(obj)
            obj.DisableAll;
            % Divide the signal around long artefacts / empty ranges
            EmptyRangesIndex = (find(diff(obj.HeartBeats)>obj.Parameters.Discontinue))';
            if ~isempty(EmptyRangesIndex) && ~(numel(EmptyRangesIndex ==1) && all(EmptyRangesIndex == 1)),
                EmptyRanges = FindContinuousRange(EmptyRangesIndex);
                EmptyRanges = [EmptyRangesIndex(EmptyRanges(:,1)), EmptyRangesIndex(EmptyRanges(:,2))];
            else
                EmptyRanges = [];
            end
            ToRemove = [obj.Artefacts;obj.RemovedWindows;EmptyRanges/obj.Frequency];
            if ~isempty(ToRemove),
            [~,IndxSort] = sort(ToRemove(:,1));
            ToRemove = ToRemove(IndxSort,:);
            
            % Merge overlaps
            IndxRmv = round(ToRemove*obj.Frequency); % We'll work in samples
            Break = false;
            if numel(IndxRmv(:,1))>1
                while ~Break
                    Break = true;
                    Reloop = false;
                    % Loop through the ranges
                    for R = 1 : numel(IndxRmv(:,1)),
                        for S = 1 : numel(IndxRmv(:,1)),
                            if S~=R,
                                if ~Reloop
                                    % Find intersections
                                    Intrsct = intersect(IndxRmv(R,1):IndxRmv(R,2),IndxRmv(S,1):IndxRmv(S,2));
                                    if ~isempty(Intrsct),
                                        % Extend ranges
                                        Min = min([IndxRmv(R,1) IndxRmv(S,1)]);
                                        IndxRmv(R,1) = Min;
                                        IndxRmv(S,1) = Min;
                                        Max = max([IndxRmv(R,2) IndxRmv(S,2)]);
                                        IndxRmv(R,2) = Max;
                                        IndxRmv(S,2) = Max;
                                        Break = false;
                                        IndxRmv = unique(IndxRmv,'rows');
                                        Reloop = true;
                                    end
                                end
                            end
                        end
                    end
                end
            end
            IndxRmv = sort(unique(IndxRmv,'rows'));
            else
                IndxRmv = [];
            end
            
            % Merge close ranges
            if ~isempty(IndxRmv),
                for KF = 2 : size(IndxRmv,1)
                    if (IndxRmv(KF,1)-IndxRmv(KF-1,2))<obj.Parameters.SlidingWindowSize,
                        IndxRmv(KF-1,2) = IndxRmv(KF,2);
                        IndxRmv(KF,1) = IndxRmv(KF-1,1);
                    end
                end
                IndxRmv = sort(unique(IndxRmv,'rows'));
                % Keep only ranges longer than the threshold
                ToRemoveEpisodesLength = (IndxRmv(:,2)-IndxRmv(:,1));
                IndxRmv(ToRemoveEpisodesLength<=obj.Parameters.Discontinue,:) = [];
                if ~isempty(IndxRmv),
                    % Deduce the ranges to process
                    GlobalRanges = [];
                    if IndxRmv(1)~=1,
                        GlobalRanges = [1 IndxRmv(1)];
                    end
                    if size(IndxRmv,1)>1,
                        for M = 1 : size(IndxRmv,1)-1
                            GlobalRanges = [GlobalRanges; IndxRmv(M,2),IndxRmv(M+1,1)];
                        end
                    end
                    if IndxRmv(1)==1 && size(IndxRmv,1)==1
                        GlobalRanges = [IndxRmv(2) numel(obj.Preprocessed)];
                    elseif IndxRmv(end,2)~= numel(obj.Preprocessed)
                        GlobalRanges = [GlobalRanges; IndxRmv(end,2),numel(obj.Preprocessed)];
                    end
                else
                    GlobalRanges = [1 numel(obj.Preprocessed)];
                end
            else
                GlobalRanges = [1 numel(obj.Preprocessed)];
            end
            
            % Call the main algorithm (first pass, forward)
            obj.LastFailed = 0;
            HeartBeats = cell(numel(GlobalRanges(:,1)),1);
            Shapes = cell(numel(GlobalRanges(:,1)),1);
            [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
            AllShapes = obj.Shapes(Indx,:);
            
            for G = 1 : numel(GlobalRanges(:,1)),
                % Retrieve the peaks for each range
                RangeIndex = find(obj.HeartBeats*obj.Frequency>=GlobalRanges(G,1) & obj.HeartBeats*obj.Frequency<=GlobalRanges(G,2));
                [~,HeartBeats{G},Shapes{G}] = obj.Projection(obj.HeartBeats(RangeIndex),AllShapes(RangeIndex,:));
            end
            HeartBeats(isempty(HeartBeats)) = [];
            try
                obj.HeartBeats = cell2mat(HeartBeats); 
            catch
                obj.HeartBeats = cell2mat(HeartBeats'); % Legacy
            end
            
            % Backward
            
            
            delete(obj.Handles.MarkersBeats)
            delete(obj.Handles.MarkersAll)
            obj.Handles.MarkersAll = plot(obj.Peaks,zeros(size(obj.Peaks)),'d','Color',[0.6 0.6 0.6],'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',[0.6 0.6 0.6]);
            obj.Handles.MarkersBeats = plot(obj.HeartBeats,zeros(size(obj.HeartBeats)),'d','Color',obj.Colors(3,:),'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',obj.Colors(3,:));
            if obj.Handles.EnableShapes.Value==1
                delete(obj.Handles.ShapesBeats);
                obj.Parameters.ShapesEnable = 1;
                obj.Handles.ShapesBeats = plot((obj.Times(obj.RangeShapes))', obj.Shapes','Color',[0.8 0.8 0.8],'LineWidth',1.5,'Parent',obj.SubPeaks);
                [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
                set(obj.Handles.ShapesBeats(Indx),{'Color'},repmat({obj.Colors(2,:)},numel(Indx),1))
                delete(obj.Handles.MarkersBeats)
                delete(obj.Handles.MarkersAll)
                obj.Handles.MarkersAll = plot(obj.Peaks,zeros(size(obj.Peaks)),'d','Color',[0.6 0.6 0.6],'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',[0.6 0.6 0.6]);
                obj.Handles.MarkersBeats = plot(obj.HeartBeats,zeros(size(obj.HeartBeats)),'d','Color',obj.Colors(3,:),'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.SubPeaks,'MarkerSize',12,'MarkerFaceColor',obj.Colors(3,:));
            end
            if obj.Parameters.RPeaksEnable
                [~,~,Indx] = intersect(obj.HeartBeats,obj.Peaks);
                delete(obj.Handles.RPeaks)
                obj.Handles.RPeaks = plot(([obj.RPeaks(:,1) obj.RPeaks(:,1)])', ([obj.RPeaks(:,2) obj.RPeaks(:,2)])','o','Color','none','MarkerSize',10,'LineWidth',1.5,'Parent',obj.SubPeaks);
                set(obj.Handles.RPeaks(Indx),{'Color'},repmat({'k'},numel(Indx),1))
            end
            if ~isempty(obj.HeartBeats)
                obj.ProcessHeartRate;
            else
                delete(obj.SubHR.Children)
                obj.SubplotVisual;
                obj.EnableAll;
            end
        end
        
        function [ScoreG,HeartBeats,Shapes] = Projection(obj,HeartBeats,Shapes,varargin)
            HeartBeats_Original = HeartBeats;
            Shapes_Original = Shapes;
            HeartBeatsSamples_Original = HeartBeats * obj.Frequency;
            % The idea is for the function to be called by itself if
            % needed, to compare how the choice of one potential peak vs
            % another would influence the analysis further, and therefore
            % make a better choice (via a global "score" for each of the
            % different possibilities)
            ScoreG = NaN;
            Abort = false;
            if isempty(varargin)
                IterNum = 1;
                % Define suspicious intervals
                SuspiciousRangeHigh = 1 / obj.Parameters.SuspiciousFrequencyHigh;
                SuspiciousRangeLow = 1 / obj.Parameters.SuspiciousFrequencyLow;
                % Find suspicious ranges
                IndexInvestigationAll = find(diff(HeartBeats)<SuspiciousRangeHigh | diff(HeartBeats)>SuspiciousRangeLow );
                if ~isempty(IndexInvestigationAll),
                    Ranges_Investigated = FindContinuousRange(IndexInvestigationAll);
                    % Convert to absolute sample number (Heartbeats index will change)
                    Ranges_Investigated_Times = HeartBeats(IndexInvestigationAll(Ranges_Investigated(:,[1 2])));
                else
                    Abort = true;
                end
            else
                IterNum = varargin{1};
                if IterNum > 3
                    return % Stop the subiteration and force the calling iteration to compute a score and choose
                else
                    IterNum = IterNum + 1;
                end
                % Assessment mode
                if isempty(HeartBeats)
                    return
                end
                Ranges_Investigated_Times = HeartBeats([1 end]);
                IndexStart = 5;
            end
            
            if ~Abort,
                if isempty(varargin)
                    % Ranges to find a starting point
                    % (good intervals stability and correlation values)
                    CorrSegmentValues = arrayfun(@(x) max(xcorr(zscore(Shapes(x,:)),obj.Template))/obj.MaxCorr,1:numel(HeartBeats));
                    CorrAdm = find(CorrSegmentValues>=0.7); % Threshold could be adjusted if needed
                    CorrRanges = FindContinuousRange(CorrAdm);
                    CorrRanges_Limited = CorrRanges(CorrRanges(:,3)>=4,1:2); % At least 4 consecutive values satisfying the criterion
                    % To full index
                    Corr_Limited_Index = false(size(HeartBeats));
                    for Int = 1 : length(CorrRanges_Limited(:,1)),
                        Corr_Limited_Index(CorrAdm(CorrRanges_Limited(Int,1)):CorrAdm(CorrRanges_Limited(Int,2))) = true;
                    end
                    % Intervals
                    Intervals = diff(HeartBeats);
                    Intervals_Limited = find(Intervals<SuspiciousRangeLow | Intervals>SuspiciousRangeHigh);
                    % To full index
                    Intervals_Limited_Index = false(size(HeartBeats));
                    for Int = 1 : length(Intervals_Limited),
                        Intervals_Limited_Index(Intervals_Limited(Int):Intervals_Limited(Int)+1) = true;
                    end
                    % Intervals stability
                    Intervals_Stable = diff(Intervals);
                    Intervals_Stable_Indx = find(abs(Intervals_Stable)<=obj.Parameters.StableIndex*obj.Frequency/1000);
                    Intervals_Stable_Range = FindContinuousRange(Intervals_Stable_Indx);
                    Intervals_Stable_Range = Intervals_Stable_Range(Intervals_Stable_Range(:,3)>=3,1:2);
                    Intervals_Stable_Range = [Intervals_Stable_Range(:,1),Intervals_Stable_Range(:,2)+2]; % Convert to real indexes (from double diff)
                    % Range to index
                    Intervals_Stable_Range_Index = false(size(HeartBeats));
                    for Int = 1 : length(Intervals_Stable_Range(:,1)),
                        Intervals_Stable_Range_Index(Intervals_Stable_Range(Int,1):Intervals_Stable_Range(Int,2)) = true;
                    end
                    % Apply the different logical indexings
                    SuitedIndex = Corr_Limited_Index & Intervals_Limited_Index & Intervals_Stable_Range_Index;
                    SuitedValues = HeartBeats(SuitedIndex);
                    
                    % If this does not give us a suitable value AT ALL, we can
                    % lower our standards
                    % (even if the "good" range is very far, it means it can be
                    % used in the reverse direction afterwards: that's OK)
                    if isempty(SuitedValues)
                        CorrSegmentValues = arrayfun(@(x) max(xcorr(zscore(Shapes(x,:)),obj.Template))/obj.MaxCorr,1:numel(HeartBeats));
                        CorrAdm = find(CorrSegmentValues>=0.5); % Threshold could be adjusted if needed
                        CorrRanges = FindContinuousRange(CorrAdm);
                        CorrRanges_Limited = CorrRanges(CorrRanges(:,3)>=4,1:2); % At least 4 consecutive values satisfying the criterion
                        % To full index
                        Corr_Limited_Index = false(size(HeartBeats));
                        for Int = 1 : length(CorrRanges_Limited(:,1)),
                            Corr_Limited_Index(CorrAdm(CorrRanges_Limited(Int,1)):CorrAdm(CorrRanges_Limited(Int,2))) = true;
                        end
                        % Intervals
                        Intervals = diff(HeartBeats);
                        Intervals_Limited = find(Intervals>SuspiciousRangeLow & Intervals<1.2*SuspiciousRangeHigh); % Decreased
                        % To full index
                        Intervals_Limited_Index = false(size(HeartBeats));
                        for Int = 1 : length(Intervals_Limited),
                            Intervals_Limited_Index(Intervals_Limited(Int):Intervals_Limited(Int)+1) = true;
                        end
                        % Intervals stability
                        Intervals_Stable = diff(Intervals);
                        Intervals_Stable_Indx = find(abs(Intervals_Stable)<=0.6 * obj.Parameters.StableIndex*obj.Frequency/1000); % Decreased
                        Intervals_Stable_Range = FindContinuousRange(Intervals_Stable_Indx);
                        Intervals_Stable_Range = Intervals_Stable_Range(Intervals_Stable_Range(:,3)>=3,1:2);
                        Intervals_Stable_Range = [Intervals_Stable_Range(:,1),Intervals_Stable_Range(:,2)+2]; % Convert to real indexes (from double diff)
                        % Range to index
                        Intervals_Stable_Range_Index = false(size(HeartBeats));
                        for Int = 1 : length(Intervals_Stable_Range(:,1)),
                            Intervals_Stable_Range_Index(Intervals_Stable_Range(Int,1):Intervals_Stable_Range(Int,2)) = true;
                        end
                        % Apply the different logical indexings
                        SuitedIndex = Corr_Limited_Index & Intervals_Limited_Index & Intervals_Stable_Range_Index;
                        SuitedValues = HeartBeats(SuitedIndex);
                    end
                    
                    if isempty(SuitedValues),
                        warning('No suitable range to start the algorithm. Aborting...');
                        return
                    end
                end
                
                % Loop through the ranges to correct
                for G = 1 : size(Ranges_Investigated_Times,1)
                    if isempty(varargin),
                        % To initialize the segment, find a preceeding stable range
                        % First, get the updated index
                        IndexStart = find(HeartBeats == Ranges_Investigated_Times(G,1));
                        % In case it's at the very beginning, ignore
                        % (processed during second pass)
                        if IndexStart<=4,
                            Break = true;
                        else
                            Break = false;
                        end
                    else
                        IndexStart = 5;
                        Break = false;
                    end
                    if ~Break,
                        BreakLoop = false;
                        % Ideally the beats just before, but otherwise we look
                        % further
                        if isempty(varargin) && ~all(SuitedIndex(IndexStart-3:IndexStart)),
                            InvestigatedPeak = find(HeartBeats<Ranges_Investigated_Times(G,1) & HeartBeats>obj.LastFailed & SuitedIndex,1,'last');
                             if isempty(InvestigatedPeak),
                                 BreakLoop = true;
                                 obj.LastFailed = Ranges_Investigated_Times(G,1);
                             end
                        else
                            InvestigatedPeak = IndexStart-1;
                        end
                        if isempty(InvestigatedPeak),
                            BreakLoop = true;
                        end
                        % Loop until the segment is processed or it fails
                        while ~BreakLoop && ~isempty(InvestigatedPeak) && InvestigatedPeak<= numel(HeartBeats) && HeartBeats(InvestigatedPeak)<=Ranges_Investigated_Times(G,2)
                            % We use the previous intervals as reference as a first
                            % approach
                            InvestigatedPeakPre = InvestigatedPeak;
                            HeartBeatsSamples = HeartBeats * obj.Frequency;
                            Before = (diff(HeartBeatsSamples(InvestigatedPeak-3:InvestigatedPeak)))';
                            Combinations = combnk(1:3,2);
                            Intervals = abs(diff(Before(Combinations),1,2));
                            if numel(Intervals(Intervals>=obj.Parameters.Outlier*obj.Frequency/1000))>1,
                                Before = Before(Combinations(Intervals<obj.Parameters.Outlier*obj.Frequency/1000,:));
                            end
                            if isempty(Before),
                                % Can happen (rarely) when bradycardia interferes too much with the thresh
                                Before = 4*obj.Parameters.Outlier*obj.Frequency/1000;
                            end
                            RangeBefore = round(mean(Before));
                            RangeBeforePre = RangeBefore;
                            xNorm = -RangeBefore/2:RangeBefore/2;
                            Norm = normpdf(xNorm,0,RangeBefore/5);
                            Norm = Norm/max(Norm);
                            
                            % Find peaks in a window just after the last peak
                            IndexInvestigated = find(HeartBeatsSamples(InvestigatedPeak:end)>(HeartBeatsSamples(InvestigatedPeak)+1.4*RangeBefore),1,'first');
                            IndexInvestigated = InvestigatedPeak+1:(InvestigatedPeak+IndexInvestigated-1);
                            if isempty(IndexInvestigated),
                                % Allow for some extension of the window
                                IndexInvestigated = find(HeartBeatsSamples(InvestigatedPeak:end)>HeartBeatsSamples(InvestigatedPeak)+1.8*RangeBefore,1,'first');
                                IndexInvestigated = InvestigatedPeak+1:(InvestigatedPeak+IndexInvestigated-1);
                            end
                            
                            % If we have more than one peak, we have to choose
                            if numel(IndexInvestigated)>1
                                % Compute scores for each of the peaks
                                Investigated = HeartBeatsSamples(IndexInvestigated);
                                PreviousAmplitude = max(Shapes(InvestigatedPeak,:))-min(Shapes(InvestigatedPeak,:));
                                CorrScore = zeros(numel(Investigated),1);
                                PositionScore = zeros(numel(Investigated),1);
                                TotalScore = zeros(numel(Investigated),1);
                                for IP = 1 : numel(IndexInvestigated),
                                    Score = Norm(find(xNorm >= HeartBeatsSamples(IndexInvestigated(IP))-HeartBeatsSamples(InvestigatedPeak)-RangeBefore,1,'first'));
                                    if ~isempty(Score),
                                        PositionScore(IP) = Score;
                                    else
                                        PositionScore(IP) = 0.1;
                                    end
                                    CorrScore(IP) = max(xcorr(zscore(Shapes(IndexInvestigated(IP),:)),obj.Template))/obj.MaxCorr;
                                    TotalScore(IP) = PositionScore(IP)*CorrScore(IP);
                                end
%                                 % If we have a very good correlation in shape,
%                                 % we can bias the scores
%                                 if max(CorrScore)>=0.9,
%                                     TotalScore(CorrScore~=max(CorrScore)) = TotalScore(CorrScore~=max(CorrScore))*0.75;
%                                 end

                                % If we have a very good candidate, we keep it
                                if any(TotalScore>=0.6),
                                    [~,BestIndex] = max(TotalScore);
                                    % We remove the peaks BEFORE the best
                                    if BestIndex ~= 1,
                                        DeleteIndex = 1:BestIndex-1;
                                        HeartBeats(IndexInvestigated(DeleteIndex)) = [];
                                        Shapes(IndexInvestigated(DeleteIndex),:) = [];
                                        if isempty(varargin)
                                            SuitedIndex(IndexInvestigated(DeleteIndex)) = [];
                                        end
                                    else
                                        DeleteIndex = [];
                                        if isempty(varargin)
                                            SuitedIndex(IndexInvestigated(1)) = 1;
                                        end
                                    end
                                    % We set the new peak for the loop
                                    InvestigatedPeak = IndexInvestigated(BestIndex-numel(DeleteIndex));
                                else
                                    % We try to extend a bit to make
                                    % sure we don't miss bradycardia
                                    IndexInvestigated = InvestigatedPeak+1:InvestigatedPeak+find(HeartBeatsSamples(InvestigatedPeak:end)>HeartBeatsSamples(InvestigatedPeak)+1.8*RangeBefore,1,'first');
                                    ToTest = IndexInvestigated;
                                    % We have to try the different possibilities
                                    % and see what's the best
                                    if isempty(ToTest),
                                        BreakLoop = true;
                                    else
                                    ScoreAll = NaN(size(ToTest));
                                    for T = 1 : numel(ToTest),
                                        IndexEnd = find(HeartBeats>(HeartBeats(InvestigatedPeak)+5*1/obj.Parameters.SuspiciousFrequencyLow),1,'first');
                                        % We don't want the other preceeding candidates to be included
                                        HeartBeatsT = HeartBeats([InvestigatedPeak-3:InvestigatedPeak ToTest(T):IndexEnd]);
                                        ShapesT = Shapes([InvestigatedPeak-3:InvestigatedPeak ToTest(T):IndexEnd],:);
                                        [ScoreAll(T),~,~] = obj.Projection(HeartBeatsT,ShapesT,IterNum);
                                    end
                                    
                                    BestIndex = find(ScoreAll>0.7,1,'first');
                                    % We remove the peaks BEFORE the best
                                    if BestIndex ~= 1,
                                        DeleteIndex = 1:BestIndex-1;
                                        HeartBeats(ToTest(DeleteIndex)) = [];
                                        Shapes(ToTest(DeleteIndex),:) = [];
                                        if isempty(varargin),
                                            SuitedIndex(ToTest(DeleteIndex)) = [];
                                        end
                                    else
                                        DeleteIndex = [];
                                        if isempty(varargin),
                                            SuitedIndex(ToTest(1)) = 1;
                                        end
                                    end
                                    % We set the new peak for the loop
                                    InvestigatedPeak = IndexInvestigated(BestIndex-numel(DeleteIndex));
                                    end
                                end
                                if ~isempty(varargin),
                                    % Compute the score
                                    HeartBeatsSamples = HeartBeats * obj.Frequency;
                                    Before = (diff(HeartBeatsSamples(1:4)))';
                                    Combinations = combnk(1:3,2);
                                    Intervals = abs(diff(Before(Combinations),1,2));
                                    if numel(Intervals(Intervals>=obj.Parameters.Outlier*obj.Frequency/1000))>1,
                                        Before = Before(Combinations(Intervals<obj.Parameters.Outlier*obj.Frequency/1000,:));
                                    end
                                    if isempty(Before),
                                        % Can happen (rarely) when bradycardia interferes too much with the thresh
                                        Before = 4*obj.Parameters.Outlier*obj.Frequency/1000;
                                    end
                                    RangeBefore = round(mean(Before));
                                    xNorm = -RangeBefore:RangeBefore;
                                    Norm = normpdf(xNorm,0,RangeBefore/3);
                                    Norm = Norm/max(Norm);
                                    PositionScore = zeros(1,numel(HeartBeatsSamples)-3);
                                    for IP = 4 : numel(HeartBeatsSamples),
                                        PScore = Norm(find(xNorm >= HeartBeatsSamples(IP)-HeartBeatsSamples(IP-1)-RangeBefore,1,'first'));
                                        if ~isempty(PScore),
                                            PositionScore(IP-3) = PScore;
                                        else
                                            PositionScore(IP-3) = 0.1;
                                        end
                                    end
                                    %                                     Amplitudes = arrayfun(@(x) abs(max(Shapes(x,:))-min(Shapes(x,:)) - max(Shapes(x-1,:))+min(Shapes(x-1,:))),4:numel(HeartBeatsSamples))/(max(obj.Template)-min(obj.Template));
                                    CorrScore = arrayfun(@(x) max(xcorr(zscore(Shapes(x,:)),obj.Template))/obj.MaxCorr, 4:numel(HeartBeatsSamples));
                                    ScoreG = mean(CorrScore .* PositionScore);
                                end
                            else
                                if ~isempty(varargin),
                                    % Compute the score
                                    HeartBeatsSamples = HeartBeats * obj.Frequency;
                                    Before = (diff(HeartBeatsSamples(1:4)))';
                                    Combinations = combnk(1:3,2);
                                    Intervals = abs(diff(Before(Combinations),1,2));
                                    if numel(Intervals(Intervals>=obj.Parameters.Outlier*obj.Frequency/1000))>1,
                                        Before = Before(Combinations(Intervals<obj.Parameters.Outlier*obj.Frequency/1000,:));
                                    end
                                    if isempty(Before),
                                        % Can happen (rarely) when bradycardia interferes too much with the thresh
                                        Before = 4*obj.Parameters.Outlier*obj.Frequency/1000;
                                    end
                                    RangeBefore = round(mean(Before));
                                    xNorm = -RangeBefore:RangeBefore;
                                    Norm = normpdf(xNorm,0,RangeBefore/3);
                                    Norm = Norm/max(Norm);
                                    PositionScore = zeros(1,numel(HeartBeatsSamples)-3);
                                    for IP = 4 : numel(HeartBeatsSamples),
                                        PScore = Norm(find(xNorm >= HeartBeatsSamples(IP)-HeartBeatsSamples(IP-1)-RangeBefore,1,'first'));
                                        if ~isempty(PScore),
                                            PositionScore(IP-3) = PScore;
                                        else
                                            PositionScore(IP-3) = 0.1;
                                        end
                                    end
                                    %                                     Amplitudes = arrayfun(@(x) abs(max(Shapes(x,:))-min(Shapes(x,:)) - max(Shapes(x-1,:))+min(Shapes(x-1,:))),4:numel(HeartBeatsSamples))/(max(obj.Template)-min(obj.Template));
                                    CorrScore = arrayfun(@(x) max(xcorr(zscore(Shapes(x,:)),obj.Template))/obj.MaxCorr, 4:numel(HeartBeatsSamples));
                                    ScoreG = mean(CorrScore .* PositionScore);
                                end
                                InvestigatedPeak = InvestigatedPeak + 1;
                            end
                        end
                    end
                end
            end
        end
    end
end