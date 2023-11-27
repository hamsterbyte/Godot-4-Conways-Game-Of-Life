using Godot;
using Godot.Collections;
using System.Net.Mime;
using System.Threading.Tasks;

public partial class Dispatcher : Node{
    [ExportGroup("Settings")]
    [Export(PropertyHint.Range, "1, 1000")]
    private int _updateFrequency = 60;

    [Export] private bool _autoStart;
    [Export] private Texture2D _dataTexture;

    [ExportGroup("Requirements")]
    [Export(PropertyHint.File)] private string _computeShader;

    [Export] private Sprite2D _renderer;

    private RenderingDevice _rd;

    private Rid _inputTexture;
    private Rid _outputTexture;
    private Rid _uniformSet;
    private Rid _shader;
    private Rid _pipeline;

    private RDUniform _inputUniform;
    private RDUniform _outputUniform;
    private Array<RDUniform> _bindings = new();

    private Image _inputImage;
    private Image _outputImage;
    private ImageTexture _renderTexture;

    private RDTextureFormat _inputFormat;
    private RDTextureFormat _outputFormat;
    private bool _processing;

    private RenderingDevice.TextureUsageBits _textureUsage =
        RenderingDevice.TextureUsageBits.StorageBit |
        RenderingDevice.TextureUsageBits.CanUpdateBit |
        RenderingDevice.TextureUsageBits.CanCopyFromBit;


    #region MAIN LOOP

    public override void _Ready(){
        CreateAndValidateImages();
        SetupComputeShader();

        if (!_autoStart) return;
        StartProcessLoop();
    }

    public override void _Input(InputEvent @event){
        if (@event is not InputEventKey key) return;
        if (key.Keycode != Key.Space || !key.Pressed) return;
        if (_processing){
            _processing = false;
        }
        else{
            StartProcessLoop();
        }
    }

    public override void _Notification(int what){
        if (what == NotificationWMCloseRequest || what == NotificationPredelete){
            CleanupGPU();
        }
    }

    #endregion
    
    #region IMAGE SETUP

    private void MergeImages(){
        int outputWidth = _outputImage.GetWidth();
        int outputHeight = _outputImage.GetHeight();
        int inputWidth = _inputImage.GetWidth();
        int inputHeight = _inputImage.GetHeight();

        int startX = (outputWidth - inputWidth) / 2;
        int startY = (outputHeight - inputHeight) / 2;

        for (int x = 0; x < inputWidth; x++){
            for (int y = 0; y < inputHeight; y++){
                Color color = _inputImage.GetPixel(x, y);
                int destX = startX + x;
                int destY = startY + y;

                if (destX >= 0 && destX < outputWidth && destY >= 0 && destY < outputHeight){
                    _outputImage.SetPixel(destX, destY, color);
                }
                
            }
        }
        _inputImage.SetData(
            1024,
            1024,
            false,
            Image.Format.L8,
            _outputImage.GetData()
        );
        
    }

    private void LinkOutputTextureToRenderer(){
        ShaderMaterial mat = _renderer.Material as ShaderMaterial;
        _renderTexture = ImageTexture.CreateFromImage(_outputImage);
        mat?.SetShaderParameter("binaryDataTexture", _renderTexture);
    }

    private void CreateAndValidateImages(){
        _outputImage = Image.Create(1024, 1024, false, Image.Format.L8);
        if (_dataTexture is null){
            FastNoiseLite noise = new(){ Frequency = .1f };
            Image noiseImage = noise.GetImage(1024, 1024);
            _inputImage = noiseImage;
        }
        else{
            _inputImage = _dataTexture.GetImage();
        }
        
        MergeImages();
        LinkOutputTextureToRenderer();

    }
    
    #endregion
    
    #region SHADER SETUP

    private void CreateRenderingDevice(){
        _rd = RenderingServer.CreateLocalRenderingDevice();
    }

    private void CreateShader(){
        RDShaderFile shaderFile = GD.Load<RDShaderFile>(_computeShader);
        RDShaderSpirV spirV = shaderFile.GetSpirV();
        _shader = _rd.ShaderCreateFromSpirV(spirV);
    }

    private void CreatePipeline(){
        _pipeline = _rd.ComputePipelineCreate(_shader);
    }

    private RDTextureFormat DefaultTextureFormat => new(){
        Width = 1024,
        Height = 1024,
        Format = RenderingDevice.DataFormat.R8Unorm,
        UsageBits = _textureUsage
    };

    private void CreateTextureFormats(){
        _inputFormat = DefaultTextureFormat;
        _outputFormat = DefaultTextureFormat;
    }

    private Rid CreateTextureAndUniform(Image image, RDTextureFormat format, int binding){
        RDTextureView view = new();
        Array<byte[]> data = new(){ image.GetData() };
        Rid texture = _rd.TextureCreate(format, view, data);
        RDUniform uniform = new(){
            UniformType = RenderingDevice.UniformType.Image,
            Binding = binding
        };
        
        uniform.AddId(texture);
        _bindings.Add(uniform);
        return texture;
    }

    private void CreateUniforms(){
        _inputTexture = CreateTextureAndUniform(_inputImage, _inputFormat, 0);
        _outputTexture = CreateTextureAndUniform(_outputImage, _outputFormat, 1);
        _uniformSet = _rd.UniformSetCreate(_bindings, _shader, 0);
    }

    private void SetupComputeShader(){
        CreateRenderingDevice();
        CreateShader();
        CreatePipeline();
        CreateTextureFormats();
        CreateUniforms();
    }



    #endregion
    
    #region PROCESSING

    private async void StartProcessLoop(){
        int frq = 1000 / _updateFrequency;
        _processing = true;
        while (_processing){
            Update();
            await Task.Delay(frq);
            Render();
        }
    }

    private void Update(){
        long computeList = _rd.ComputeListBegin();
        _rd.ComputeListBindComputePipeline(computeList, _pipeline);
        _rd.ComputeListBindUniformSet(computeList, _uniformSet, 0);
        _rd.ComputeListDispatch(computeList, 32, 32, 1);
        _rd.ComputeListEnd();
        _rd.Submit();
    }

    private void Render(){
        _rd.Sync();
        byte[] bytes = _rd.TextureGetData(_outputTexture, 0);
        _rd.TextureUpdate(_inputTexture, 0, bytes);
        _outputImage.SetData(1024, 1024, false, Image.Format.L8, bytes);
        _renderTexture.Update(_outputImage);
    }

    private void CleanupGPU(){
        if (_rd is null) return;
        _rd.FreeRid(_inputTexture);
        _rd.FreeRid(_outputTexture);
        _rd.FreeRid(_uniformSet);
        _rd.FreeRid(_pipeline);
        _rd.FreeRid(_shader);
        _rd.Free();
        _rd = null;
    }
    
    
    
    #endregion

}