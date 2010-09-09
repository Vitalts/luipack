unit LuiREST;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttp, contnrs, HTTPDefs, fpjson;

type
  TCustomRESTResource = class;
  TRESTResourceDef = class;
  TRESTResourceStore = class;
  TCustomRESTResourceClass = class of TCustomRESTResource;

  { TCustomRESTResource }

  TCustomRESTResource = class(TPersistent)
  private
    FSubPathResources: TRESTResourceStore;
    FSubPathParamName: String;
  protected
    procedure RegisterSubPathResource(const ResourceId: ShortString; Resource: TCustomRESTResource; ResourceClass: TCustomRESTResourceClass);
    procedure SetDefaultSubResource(const ParamName: String; Resource: TCustomRESTResource; ResourceClass: TCustomRESTResourceClass);
  public
    destructor Destroy; override;
    procedure HandleDelete(URIParams: TJSONObject; ARequest: TRequest; AResponse: TResponse); virtual;
    procedure HandleGet(URIParams: TJSONObject; ARequest: TRequest; AResponse: TResponse); virtual;
    procedure HandlePost(URIParams: TJSONObject; ARequest: TRequest; AResponse: TResponse); virtual;
    procedure HandlePut(URIParams: TJSONObject; ARequest: TRequest; AResponse: TResponse); virtual;
    procedure HandleSubPath(const SubPath: String; URIParams: TJSONObject; var SubPathResourceDef: TRESTResourceDef); virtual;
  end;

  { TRESTResourceDef }

  TRESTResourceDef = class
  private
    FResource: TCustomRESTResource;
    FResourceClass: TCustomRESTResourceClass;
  public
    constructor Create(AResource: TCustomRESTResource; AResourceClass: TCustomRESTResourceClass);
    destructor Destroy; override;
    property ResourceClass: TCustomRESTResourceClass read FResourceClass write FResourceClass;
    property Resource: TCustomRESTResource read FResource write FResource;
  end;

  { TRESTResourceStore }

  TRESTResourceStore = class
  private
    FDefaultResourceDef: TRESTResourceDef;
    FList: TFPHashObjectList;
    procedure SetDefaultResourceDef(const Value: TRESTResourceDef);
    property DefaultResourceDef: TRESTResourceDef read FDefaultResourceDef write SetDefaultResourceDef;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const ResourceId: ShortString): TRESTResourceDef;
    function Get(const ResourceId: ShortString): TCustomRESTResource;
    procedure RegisterResource(const ResourceId: ShortString; Resource: TCustomRESTResource; ResourceClass: TCustomRESTResourceClass);
  end;

  TCreateRESTResourceEvent = procedure(Resource: TCustomRESTResource) of object;

  { TRESTServiceModule }

  TRESTServiceModule = class(TCustomHTTPModule)
  private
    FBaseResources: TRESTResourceStore;
    FOnCreateResource: TCreateRESTResourceEvent;
    FRootPath: String;
    procedure SetRootPath(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure HandleRequest(ARequest: TRequest; AResponse: TResponse); override;
    procedure RegisterResource(const ResourceName: ShortString; ResourceClass: TCustomRESTResourceClass);
  published
    property RootPath: String read FRootPath write SetRootPath;
    //events
    property OnCreateResource: TCreateRESTResourceEvent read FOnCreateResource write FOnCreateResource;
  end;

implementation

{ TRESTServiceModule }

procedure TRESTServiceModule.SetRootPath(const Value: String);
begin
  if Value <> '' then
  begin
    if Value[1] <> '/' then
      FRootPath := '/' + Value
    else
      FRootPath := Value;
    if Value[Length(Value)] <> '/' then
      FRootPath := FRootPath + '/';
  end
  else
    FRootPath := '/';
end;

constructor TRESTServiceModule.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBaseResources := TRESTResourceStore.Create;
end;

destructor TRESTServiceModule.Destroy;
begin
  FBaseResources.Destroy;
  inherited Destroy;
end;

procedure TRESTServiceModule.HandleRequest(ARequest: TRequest;
  AResponse: TResponse);


  function GetURIPart(const S : String; var StrOffset: Integer) : String;
  var
    P : integer;
  begin
    if StrOffset > Length(S) then
      Exit('');
    P := IndexChar(S[StrOffset], Length(S) - StrOffset + 1, '/');
    if P = -1 then
      P := Length(S) + 1;
    Result := Copy(S, StrOffset, P);
    Inc(StrOffset, P + 1);
  end;

var
  URIPath, URIPart, NextURIPart, MethodStr: String;
  i, PartOffset: Integer;
  ResourceDef, NextResourceDef: TRESTResourceDef;
  URIParams: TJSONObject;
begin
  URIParams := TJSONObject.Create;
  MethodStr := UpperCase(ARequest.Method);
  URIPath := ARequest.PathInfo;
  i := Pos(FRootPath, URIPath);
  if i <> 0 then
  begin
    PartOffset := i + Length(FRootPath);
    URIPart := GetURIPart(URIPath, PartOffset);
    //the first part is by convention a collection
    if URIPart = '' then
      raise Exception.CreateFmt('REST resource path not found. PartOffset %d, URIPath: %s', [PartOffset, URIPath]);
    ResourceDef := FBaseResources.Find(URIPart);
    if ResourceDef = nil then
      raise Exception.CreateFmt('REST resource "%s" not registered', [URIPart]);

    //todo: handle OnCreate
    if ResourceDef.Resource = nil then
    begin
      ResourceDef.Resource := ResourceDef.ResourceClass.Create;
      if Assigned(FOnCreateResource) then
        FOnCreateResource(ResourceDef.Resource);
    end;

    NextURIPart := GetURIPart(URIPath, PartOffset);
    while NextURIPart <> '' do
    begin
      NextResourceDef := nil;
      ResourceDef.Resource.HandleSubPath(NextURIPart, URIParams, NextResourceDef);

      if NextResourceDef = nil then
      begin
        MethodStr := BoolToStr(Boolean(ResourceDef.Resource.FSubPathResources = nil), True);
        raise Exception.CreateFmt('REST resource "%s" not registered. Resource: %s, SubPathRes: %s',
          [NextURIPart, ResourceDef.Resource.ClassName, MethodStr]);
      end;

      ResourceDef := NextResourceDef;

      if ResourceDef.Resource = nil then
      begin
        ResourceDef.Resource := ResourceDef.ResourceClass.Create;
        if Assigned(FOnCreateResource) then
          FOnCreateResource(ResourceDef.Resource);
      end;

      NextURIPart := GetURIPart(URIPath, PartOffset);
    end;

    //todo: move get to top
    if MethodStr = 'PUT' then
      ResourceDef.Resource.HandlePut(URIParams, ARequest, AResponse)
    else if MethodStr = 'POST' then
      ResourceDef.Resource.HandlePost(URIParams, ARequest, AResponse)
    else if MethodStr = 'DELETE' then
      ResourceDef.Resource.HandleDelete(URIParams, ARequest, AResponse)
    else
      ResourceDef.Resource.HandleGet(URIParams, ARequest, AResponse);
  end
  else
    raise Exception.CreateFmt('REST root path not found. URIPath: %s RootPath: "%s"', [URIPath, FRootPath]);
  URIParams.Destroy;
end;

procedure TRESTServiceModule.RegisterResource(const ResourceName: ShortString; ResourceClass: TCustomRESTResourceClass);
begin
  FBaseResources.RegisterResource(ResourceName, nil, ResourceClass);
end;

{ TCustomRESTResource }

procedure TCustomRESTResource.RegisterSubPathResource(const ResourceId: ShortString;
  Resource: TCustomRESTResource; ResourceClass: TCustomRESTResourceClass);
begin
  if FSubPathResources = nil then
    FSubPathResources := TRESTResourceStore.Create;
  FSubPathResources.RegisterResource(ResourceId, Resource, ResourceClass);
end;

procedure TCustomRESTResource.SetDefaultSubResource(const ParamName: String;
  Resource: TCustomRESTResource; ResourceClass: TCustomRESTResourceClass);
begin
  if FSubPathResources = nil then
    FSubPathResources := TRESTResourceStore.Create;
  //the class or the instance must be <> nil
  if (PtrInt(Resource) + PtrInt(ResourceClass)) = 0 then
    raise Exception.CreateFmt('SetDefaultResource (%s): Class or Instance must be <> nil', [ParamName]);
  FSubPathParamName := ParamName;
  FSubPathResources.DefaultResourceDef := TRESTResourceDef.Create(Resource, ResourceClass);
end;

destructor TCustomRESTResource.Destroy;
begin
  FSubPathResources.Free;
  inherited Destroy;
end;

procedure TCustomRESTResource.HandleSubPath(const SubPath: String; URIParams: TJSONObject; var SubPathResourceDef: TRESTResourceDef);
begin
  if FSubPathResources <> nil then
  begin
    SubPathResourceDef := FSubPathResources.Find(SubPath);
    if SubPathResourceDef = nil then
    begin
      SubPathResourceDef := FSubPathResources.DefaultResourceDef;
      URIParams.Strings[FSubPathParamName] := SubPath;
    end;
  end;
end;

procedure TCustomRESTResource.HandleDelete(URIParams: TJSONObject;
  ARequest: TRequest; AResponse: TResponse);
begin
  //
end;

procedure TCustomRESTResource.HandleGet(URIParams: TJSONObject; ARequest: TRequest;
  AResponse: TResponse);
begin
  //
end;

procedure TCustomRESTResource.HandlePost(URIParams: TJSONObject; ARequest: TRequest;
  AResponse: TResponse);
begin
  //
end;

procedure TCustomRESTResource.HandlePut(URIParams: TJSONObject; ARequest: TRequest;
  AResponse: TResponse);
begin
  //
end;

{ TRESTResourceStore }


procedure TRESTResourceStore.SetDefaultResourceDef(const Value: TRESTResourceDef);
begin
  if Value = FDefaultResourceDef then
    Exit;
  FreeAndNil(FDefaultResourceDef);
  FDefaultResourceDef := Value;
end;

constructor TRESTResourceStore.Create;
begin
  FList := TFPHashObjectList.Create(True);
end;

destructor TRESTResourceStore.Destroy;
begin
  FList.Destroy;
  FDefaultResourceDef.Free;
  inherited Destroy;
end;

function TRESTResourceStore.Find(const ResourceId: ShortString): TRESTResourceDef;
begin
  Result := TRESTResourceDef(FList.Find(ResourceId));
end;

function TRESTResourceStore.Get(const ResourceId: ShortString): TCustomRESTResource;
var
  Def: TRESTResourceDef;
begin
  Def := TRESTResourceDef(FList.Find(ResourceId));
  if Def = nil then
    Def := DefaultResourceDef;
  Result := Def.Resource;
  //todo: notify about creation
  if (Result = nil) and (Def.ResourceClass <> nil) then
    Result := Def.ResourceClass.Create;
end;

procedure TRESTResourceStore.RegisterResource(const ResourceId: ShortString;
  Resource: TCustomRESTResource; ResourceClass: TCustomRESTResourceClass);
var
  Def: TRESTResourceDef;
begin
  //the class or the instance must be <> nil
  if (PtrUInt(Resource) + PtrUInt(ResourceClass)) = 0 then
    raise Exception.CreateFmt('RegisterResource (%s): Class or Instance must be <> nil', [ResourceId]);
  Def := TRESTResourceDef.Create(Resource, ResourceClass);
  FList.Add(ResourceId, Def);
end;

{ TRESTResourceDef }

constructor TRESTResourceDef.Create(AResource: TCustomRESTResource;
  AResourceClass: TCustomRESTResourceClass);
begin
  inherited Create;
  FResource := AResource;
  FResourceClass := AResourceClass;
end;

destructor TRESTResourceDef.Destroy;
begin
  FResource.Free;
  inherited Destroy;
end;

end.
