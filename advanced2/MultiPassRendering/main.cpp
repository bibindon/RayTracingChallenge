#pragma comment( lib, "d3d9.lib" )
#if defined(DEBUG) || defined(_DEBUG)
#pragma comment( lib, "d3dx9d.lib" )
#else
#pragma comment( lib, "d3dx9.lib" )
#endif

#include <d3d9.h>
#include <d3dx9.h>
#include <string>
#include <tchar.h>
#include <cassert>
#include <crtdbg.h>
#include <vector>

static const float g_fCameraDistance = 15.0f;

static const float g_fCameraMoveSpeed = 0.01f;

#define SAFE_RELEASE(p) { if (p) { (p)->Release(); (p) = NULL; } }

LPDIRECT3D9 g_pD3D = NULL;
LPDIRECT3DDEVICE9 g_pd3dDevice = NULL;
LPD3DXFONT g_pFont = NULL;

struct MeshData
{
    LPD3DXMESH pMesh = NULL;
    std::vector<D3DMATERIAL9> materials;
    std::vector<LPDIRECT3DTEXTURE9> textures;
    DWORD numMaterials = 0;
    D3DXVECTOR3 position;
};

std::vector<MeshData> g_meshes;

LPD3DXMESH g_pMeshSphere = NULL;

LPD3DXEFFECT g_pEffect1 = NULL;
LPD3DXEFFECT g_pEffect2 = NULL;
LPD3DXEFFECT g_pEffect3 = NULL;

bool g_bClose = false;
bool g_bRayTracingEnabled = true;
bool g_bSSAOEnabled = true;

// === 変更: RT を 3 枚用意 ===
LPDIRECT3DTEXTURE9 g_pRenderTarget = NULL;
LPDIRECT3DTEXTURE9 g_pRenderTarget2 = NULL;
LPDIRECT3DTEXTURE9 g_pRenderTarget3 = NULL;
LPDIRECT3DTEXTURE9 g_pRenderTarget4 = NULL;

// フルスクリーンクアッド用
LPDIRECT3DVERTEXDECLARATION9 g_pQuadDecl = NULL;

// 追加: スプライト
LPD3DXSPRITE g_pSprite = NULL;

struct QuadVertex
{
    float x, y, z, w; // クリップ空間（-1..1, w=1）
    float u, v;       // テクスチャ座標
};

static void TextDraw(LPD3DXFONT pFont, TCHAR* text, int X, int Y);
static void InitD3D(HWND hWnd);
static void Cleanup();

static void RenderPass1();
static void RenderPass2();
static void RenderPass3();
static void DrawFullscreenQuad();

LRESULT WINAPI MsgProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

extern int WINAPI _tWinMain(_In_ HINSTANCE hInstance,
                            _In_opt_ HINSTANCE hPrevInstance,
                            _In_ LPTSTR lpCmdLine,
                            _In_ int nCmdShow);

int WINAPI _tWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPTSTR lpCmdLine,
                     _In_ int nCmdShow)
{
    _CrtSetDbgFlag(_CRTDBG_ALLOC_MEM_DF | _CRTDBG_LEAK_CHECK_DF);

    WNDCLASSEX wc { };
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.style = CS_CLASSDC;
    wc.lpfnWndProc = MsgProc;
    wc.cbClsExtra = 0;
    wc.cbWndExtra = 0;
    wc.hInstance = GetModuleHandle(NULL);
    wc.hIcon = NULL;
    wc.hCursor = NULL;
    wc.hbrBackground = NULL;
    wc.lpszMenuName = NULL;
    wc.lpszClassName = _T("Window1");
    wc.hIconSm = NULL;

    ATOM atom = RegisterClassEx(&wc);
    assert(atom != 0);

    RECT rect;
    SetRect(&rect, 0, 0, 1600, 900);
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);
    rect.right = rect.right - rect.left;
    rect.bottom = rect.bottom - rect.top;
    rect.top = 0;
    rect.left = 0;

    HWND hWnd = CreateWindow(_T("Window1"),
                             _T("Hello DirectX9 World !!"),
                             WS_OVERLAPPEDWINDOW,
                             CW_USEDEFAULT,
                             CW_USEDEFAULT,
                             rect.right,
                             rect.bottom,
                             NULL,
                             NULL,
                             wc.hInstance,
                             NULL);

    InitD3D(hWnd);
    ShowWindow(hWnd, SW_SHOWDEFAULT);
    UpdateWindow(hWnd);

    MSG msg;

    while (true)
    {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
        {
            DispatchMessage(&msg);
        }
        else
        {
            Sleep(16);

            RenderPass1();
            RenderPass2();
            RenderPass3();
        }

        if (g_bClose)
        {
            break;
        }
    }

    Cleanup();

    UnregisterClass(_T("Window1"), wc.hInstance);
    return 0;
}

void TextDraw(LPD3DXFONT pFont, TCHAR* text, int X, int Y)
{
    RECT rect = { X, Y, 0, 0 };

    HRESULT hResult = pFont->DrawText(NULL,
                                      text,
                                      -1,
                                      &rect,
                                      DT_LEFT | DT_NOCLIP,
                                      D3DCOLOR_ARGB(255, 0, 0, 0));

    assert((int)hResult >= 0);
}

void InitD3D(HWND hWnd)
{
    HRESULT hResult = E_FAIL;

    g_pD3D = Direct3DCreate9(D3D_SDK_VERSION);
    assert(g_pD3D != NULL);

    D3DPRESENT_PARAMETERS d3dpp;
    ZeroMemory(&d3dpp, sizeof(d3dpp));
    d3dpp.Windowed = TRUE;
    d3dpp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    d3dpp.BackBufferFormat = D3DFMT_UNKNOWN;
    d3dpp.BackBufferCount = 1;
    d3dpp.MultiSampleType = D3DMULTISAMPLE_NONE;
    d3dpp.MultiSampleQuality = 0;
    d3dpp.EnableAutoDepthStencil = TRUE;
    d3dpp.AutoDepthStencilFormat = D3DFMT_D16;
    d3dpp.hDeviceWindow = hWnd;
    d3dpp.Flags = 0;
    d3dpp.FullScreen_RefreshRateInHz = D3DPRESENT_RATE_DEFAULT;
    d3dpp.PresentationInterval = D3DPRESENT_INTERVAL_DEFAULT;

    hResult = g_pD3D->CreateDevice(D3DADAPTER_DEFAULT,
                                   D3DDEVTYPE_HAL,
                                   hWnd,
                                   D3DCREATE_HARDWARE_VERTEXPROCESSING,
                                   &d3dpp,
                                   &g_pd3dDevice);

    if (FAILED(hResult))
    {
        hResult = g_pD3D->CreateDevice(D3DADAPTER_DEFAULT,
                                       D3DDEVTYPE_HAL,
                                       hWnd,
                                       D3DCREATE_SOFTWARE_VERTEXPROCESSING,
                                       &d3dpp,
                                       &g_pd3dDevice);
        assert(hResult == S_OK);
    }

    hResult = D3DXCreateFont(g_pd3dDevice,
                             20,
                             0,
                             FW_HEAVY,
                             1,
                             FALSE,
                             SHIFTJIS_CHARSET,
                             OUT_TT_ONLY_PRECIS,
                             CLEARTYPE_NATURAL_QUALITY,
                             FF_DONTCARE,
                             _T("MS Gothic"),
                             &g_pFont);
    assert(hResult == S_OK);

    // 4 つのカラーキューブ + 地面・壁を読み込み
    struct MeshLoadInfo
    {
        const TCHAR* filename;
        D3DXVECTOR3 position;
    };
    MeshLoadInfo loadInfos[] =
    {
        { _T("cube_red.x"),       D3DXVECTOR3(-2.0f,   0.0f, -2.0f) },
        { _T("cube_white.x"),     D3DXVECTOR3(-2.0f,   0.0f,  2.0f) },
        { _T("cube_green.x"),     D3DXVECTOR3( 2.0f,   0.5f,  2.0f) },
        { _T("cube_blue.x"),      D3DXVECTOR3( -6.0f,   0.0f,  2.0f) },
        { _T("cube_green.x"),     D3DXVECTOR3( 4.0f,   5.0f, -2.0f) },
        { _T("cube_blue.x"),      D3DXVECTOR3(-4.0f,   3.75f, -4.0f) },
        { _T("cube_white_big.x"), D3DXVECTOR3( 0.0f, -11.0f,  0.0f) },
        { _T("cube_white_big.x"), D3DXVECTOR3( 0.0f,  15.0f,  0.0f) },
        { _T("cube_red_big.x"),   D3DXVECTOR3(14.0f,  -9.0f,  0.0f) },
        { _T("cube_white_big.x"), D3DXVECTOR3(-10.0f,  -7.5f,  14.0f) },
    };

    const int meshCount = _countof(loadInfos);
    g_meshes.resize(meshCount);
    for (int mi = 0; mi < meshCount; mi++)
    {
        LPD3DXBUFFER pD3DXMtrlBuffer = NULL;

        hResult = D3DXLoadMeshFromX(loadInfos[mi].filename,
                                    D3DXMESH_SYSTEMMEM,
                                    g_pd3dDevice,
                                    NULL,
                                    &pD3DXMtrlBuffer,
                                    NULL,
                                    &g_meshes[mi].numMaterials,
                                    &g_meshes[mi].pMesh);
        assert(hResult == S_OK);

        g_meshes[mi].position = loadInfos[mi].position;

        D3DXMATERIAL* d3dxMaterials = (D3DXMATERIAL*)pD3DXMtrlBuffer->GetBufferPointer();
        g_meshes[mi].materials.resize(g_meshes[mi].numMaterials);
        g_meshes[mi].textures.resize(g_meshes[mi].numMaterials);

        for (DWORD i = 0; i < g_meshes[mi].numMaterials; i++)
        {
            g_meshes[mi].materials[i] = d3dxMaterials[i].MatD3D;
            g_meshes[mi].materials[i].Ambient = g_meshes[mi].materials[i].Diffuse;
            g_meshes[mi].textures[i] = NULL;

            std::string pTexPath(d3dxMaterials[i].pTextureFilename);

            if (!pTexPath.empty())
            {
                bool bUnicode = false;
#ifdef UNICODE
                bUnicode = true;
#endif
                if (!bUnicode)
                {
                    hResult = D3DXCreateTextureFromFileA(g_pd3dDevice, pTexPath.c_str(), &g_meshes[mi].textures[i]);
                    assert(hResult == S_OK);
                }
                else
                {
                    int len = MultiByteToWideChar(CP_ACP, 0, pTexPath.c_str(), -1, nullptr, 0);
                    std::wstring pTexPathW(len, 0);
                    MultiByteToWideChar(CP_ACP, 0, pTexPath.c_str(), -1, &pTexPathW[0], len);

                    hResult = D3DXCreateTextureFromFileW(g_pd3dDevice, pTexPathW.c_str(), &g_meshes[mi].textures[i]);
                    assert(hResult == S_OK);
                }
            }
        }

        hResult = pD3DXMtrlBuffer->Release();
        assert(hResult == S_OK);
    }

    hResult = D3DXCreateEffectFromFile(g_pd3dDevice,
                                       _T("simple.fx"),
                                       NULL,
                                       NULL,
                                       D3DXSHADER_DEBUG,
                                       NULL,
                                       &g_pEffect1,
                                       NULL);
    assert(hResult == S_OK);

    hResult = D3DXCreateEffectFromFile(g_pd3dDevice,
                                       _T("simple2.fx"),
                                       NULL,
                                       NULL,
                                       D3DXSHADER_DEBUG,
                                       NULL,
                                       &g_pEffect2,
                                       NULL);
    assert(hResult == S_OK);

    hResult = D3DXCreateEffectFromFile(g_pd3dDevice,
                                       _T("simple3.fx"),
                                       NULL,
                                       NULL,
                                       D3DXSHADER_DEBUG,
                                       NULL,
                                       &g_pEffect3,
                                       NULL);
    assert(hResult == S_OK);

    hResult = D3DXCreateSphere(g_pd3dDevice,
                               500.f,
                               32,
                               32,
                               &g_pMeshSphere,
                               NULL);
    assert(hResult == S_OK);

    // RT0: color, RT1: high-precision depth, RT2: normal, RT3: post-process
    hResult = D3DXCreateTexture(g_pd3dDevice,
                                1600, 900,
                                1,
                                D3DUSAGE_RENDERTARGET,
                                D3DFMT_A8R8G8B8,
                                D3DPOOL_DEFAULT,
                                &g_pRenderTarget);
    assert(hResult == S_OK);

    hResult = D3DXCreateTexture(g_pd3dDevice,
                                 1600, 900,
                                 1,
                                 D3DUSAGE_RENDERTARGET,
                                 D3DFMT_A16B16G16R16F,
                                 D3DPOOL_DEFAULT,
                                 &g_pRenderTarget2);
    assert(hResult == S_OK);

    hResult = D3DXCreateTexture(g_pd3dDevice,
                                 1600, 900,
                                 1,
                                 D3DUSAGE_RENDERTARGET,
                                 D3DFMT_A8R8G8B8,
                                 D3DPOOL_DEFAULT,
                                 &g_pRenderTarget3);
    assert(hResult == S_OK);

    hResult = D3DXCreateTexture(g_pd3dDevice,
                                 1600, 900,
                                 1,
                                 D3DUSAGE_RENDERTARGET,
                                 D3DFMT_A8R8G8B8,
                                 D3DPOOL_DEFAULT,
                                 &g_pRenderTarget4);
    assert(hResult == S_OK);

    // フルスクリーンクアッドの頂宣言
    D3DVERTEXELEMENT9 elems[] =
    {
        { 0,  0, D3DDECLTYPE_FLOAT4, D3DDECLMETHOD_DEFAULT, D3DDECLUSAGE_POSITION, 0 },
        { 0, 16, D3DDECLTYPE_FLOAT2, D3DDECLMETHOD_DEFAULT, D3DDECLUSAGE_TEXCOORD, 0 },
        D3DDECL_END()
    };
    hResult = g_pd3dDevice->CreateVertexDeclaration(elems, &g_pQuadDecl);
    assert(hResult == S_OK);

    // スプライト
    hResult = D3DXCreateSprite(g_pd3dDevice, &g_pSprite);
    assert(hResult == S_OK);
}

void Cleanup()
{
    for (auto& mesh : g_meshes)
    {
        for (auto& texture : mesh.textures)
        {
            SAFE_RELEASE(texture);
        }
        SAFE_RELEASE(mesh.pMesh);
    }
    g_meshes.clear();
    SAFE_RELEASE(g_pMeshSphere);
    SAFE_RELEASE(g_pEffect1);
    SAFE_RELEASE(g_pEffect2);
    SAFE_RELEASE(g_pEffect3);
    SAFE_RELEASE(g_pFont);

    // 追加: 解放漏れ防止
    SAFE_RELEASE(g_pRenderTarget);
    SAFE_RELEASE(g_pRenderTarget2);
    SAFE_RELEASE(g_pRenderTarget3);
    SAFE_RELEASE(g_pRenderTarget4);
    SAFE_RELEASE(g_pQuadDecl);
    SAFE_RELEASE(g_pSprite);

    SAFE_RELEASE(g_pd3dDevice);
    SAFE_RELEASE(g_pD3D);
}

void RenderPass1()
{
    HRESULT hResult = E_FAIL;

    // 既存の RT0 を保存
    LPDIRECT3DSURFACE9 pOldRT0 = NULL;
    hResult = g_pd3dDevice->GetRenderTarget(0, &pOldRT0);
    assert(hResult == S_OK);

    // 3 枚の RT サーフェスを取得
    LPDIRECT3DSURFACE9 pRT0 = NULL;
    LPDIRECT3DSURFACE9 pRT1 = NULL;
    LPDIRECT3DSURFACE9 pRT2 = NULL;
    hResult = g_pRenderTarget->GetSurfaceLevel(0, &pRT0);  assert(hResult == S_OK);
    hResult = g_pRenderTarget2->GetSurfaceLevel(0, &pRT1); assert(hResult == S_OK);
    hResult = g_pRenderTarget3->GetSurfaceLevel(0, &pRT2); assert(hResult == S_OK);

    hResult = g_pd3dDevice->SetRenderTarget(0, pRT0); assert(hResult == S_OK);
    hResult = g_pd3dDevice->SetRenderTarget(1, NULL); assert(hResult == S_OK);
    hResult = g_pd3dDevice->SetRenderTarget(2, NULL); assert(hResult == S_OK);

    static float f = 0.0f;
    f += g_fCameraMoveSpeed;

    D3DXMATRIX View, Proj;

    D3DXMatrixPerspectiveFovLH(&Proj,
                               D3DXToRadian(45),
                               1600.0f / 900.0f,
                               1.0f,
                               100.0f);

    D3DXVECTOR3 eye(g_fCameraDistance * sinf(f), 3, -g_fCameraDistance * cosf(f));
    D3DXVECTOR3 at(0, 1, 0);
    D3DXVECTOR3 up(0, 1, 0);
    D3DXMatrixLookAtLH(&View, &eye, &at, &up);
    hResult = g_pd3dDevice->Clear(0, NULL,
                                  D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER,
                                  D3DCOLOR_XRGB(135, 206, 235),
                                  1.0f, 0);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->SetRenderTarget(0, pRT1); assert(hResult == S_OK);
    hResult = g_pd3dDevice->Clear(0, NULL,
                                  D3DCLEAR_TARGET,
                                  D3DCOLOR_ARGB(255, 255, 255, 255),
                                  1.0f, 0);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->SetRenderTarget(0, pRT2); assert(hResult == S_OK);
    hResult = g_pd3dDevice->Clear(0, NULL,
                                  D3DCLEAR_TARGET,
                                  D3DCOLOR_ARGB(255, 128, 128, 128),
                                  1.0f, 0);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->SetRenderTarget(0, pRT0); assert(hResult == S_OK);
    hResult = g_pd3dDevice->SetRenderTarget(1, pRT1); assert(hResult == S_OK);
    hResult = g_pd3dDevice->SetRenderTarget(2, pRT2); assert(hResult == S_OK);

    hResult = g_pd3dDevice->BeginScene(); assert(hResult == S_OK);

    // タイトル
    TCHAR msg[100];
    _tcscpy_s(msg, 100, _T("Ray Tracing Challenge"));
    TextDraw(g_pFont, msg, 0, 0);

    // === 変更: MRT 用テクニックを使用 ===
    hResult = g_pEffect1->SetTechnique("TechniqueMRT");
    assert(hResult == S_OK);

    // ビュー行列をシェーダーに渡す（法線のビュー空間変換用）
    hResult = g_pEffect1->SetMatrix("g_matView", &View);
    assert(hResult == S_OK);
    D3DXVECTOR4 defaultBaseColor(1.0f, 1.0f, 1.0f, 1.0f);
    hResult = g_pEffect1->SetVector("g_baseColor", &defaultBaseColor);
    assert(hResult == S_OK);

    UINT numPass = 0;
    hResult = g_pEffect1->Begin(&numPass, 0); assert(hResult == S_OK);
    hResult = g_pEffect1->BeginPass(0);       assert(hResult == S_OK);

    // 4 つのカラーキューブを描画
    hResult = g_pEffect1->SetBool("g_bUseTexture", TRUE); assert(hResult == S_OK);
    for (size_t mi = 0; mi < g_meshes.size(); mi++)
    {
        D3DXMATRIX matWorld;
        D3DXMatrixTranslation(&matWorld,
                              g_meshes[mi].position.x,
                              g_meshes[mi].position.y,
                              g_meshes[mi].position.z);
        D3DXMATRIX matWVP = matWorld * View * Proj;
        hResult = g_pEffect1->SetMatrix("g_matWorldViewProj", &matWVP);
        assert(hResult == S_OK);

        for (DWORD i = 0; i < g_meshes[mi].numMaterials; i++)
        {
            hResult = g_pEffect1->SetTexture("texture1", g_meshes[mi].textures[i]); assert(hResult == S_OK);
            hResult = g_pEffect1->CommitChanges();                                    assert(hResult == S_OK);
            hResult = g_meshes[mi].pMesh->DrawSubset(i);                              assert(hResult == S_OK);
        }
    }

    // 球（テクスチャなし）
    if (true)
    {
        D3DXMATRIX matIdentity;
        D3DXMatrixIdentity(&matIdentity);
        D3DXMATRIX matWVP = matIdentity * View * Proj;
        hResult = g_pEffect1->SetMatrix("g_matWorldViewProj", &matWVP);
        assert(hResult == S_OK);

        D3DXVECTOR4 sphereBaseColor(0.53f, 0.81f, 0.92f, 1.0f);
        hResult = g_pEffect1->SetVector("g_baseColor", &sphereBaseColor);
        assert(hResult == S_OK);
        hResult = g_pEffect1->SetBool("g_bUseTexture", FALSE); assert(hResult == S_OK);
        hResult = g_pEffect1->SetTexture("texture1", NULL);    assert(hResult == S_OK);
        hResult = g_pEffect1->CommitChanges();                 assert(hResult == S_OK);
        hResult = g_pMeshSphere->DrawSubset(0);                assert(hResult == S_OK);
    }

    hResult = g_pEffect1->EndPass(); assert(hResult == S_OK);
    hResult = g_pEffect1->End();     assert(hResult == S_OK);

    hResult = g_pd3dDevice->EndScene(); assert(hResult == S_OK);

    // MRT を解除してバックバッファへ戻す
    hResult = g_pd3dDevice->SetRenderTarget(2, NULL);    assert(hResult == S_OK);
    hResult = g_pd3dDevice->SetRenderTarget(1, NULL);    assert(hResult == S_OK);
    hResult = g_pd3dDevice->SetRenderTarget(0, pOldRT0); assert(hResult == S_OK);

    SAFE_RELEASE(pRT0);
    SAFE_RELEASE(pRT1);
    SAFE_RELEASE(pRT2);
    SAFE_RELEASE(pOldRT0);
}

void RenderPass2()
{
    HRESULT hResult = E_FAIL;

    LPDIRECT3DSURFACE9 pOldRT0 = NULL;
    hResult = g_pd3dDevice->GetRenderTarget(0, &pOldRT0);
    assert(hResult == S_OK);

    LPDIRECT3DSURFACE9 pRT0 = NULL;
    hResult = g_pRenderTarget4->GetSurfaceLevel(0, &pRT0);
    assert(hResult == S_OK);
    hResult = g_pd3dDevice->SetRenderTarget(0, pRT0);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->Clear(0, NULL,
                                  D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER,
                                  D3DCOLOR_XRGB(0, 0, 0),
                                  1.0f, 0);
    assert(hResult == S_OK);

    // 2D 全面描画なので Z 無効
    hResult = g_pd3dDevice->SetRenderState(D3DRS_ZENABLE, FALSE);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->BeginScene(); assert(hResult == S_OK);

    // フルスクリーン: RT0 を simple2.fx で表示
    hResult = g_pEffect2->SetTechnique("Technique1");       assert(hResult == S_OK);

    UINT numPass = 0;
    hResult = g_pEffect2->Begin(&numPass, 0);               assert(hResult == S_OK);
    hResult = g_pEffect2->BeginPass(0);                     assert(hResult == S_OK);

    hResult = g_pEffect2->SetTexture("texture1", g_pRenderTarget);  assert(hResult == S_OK);
    hResult = g_pEffect2->SetTexture("texture2", g_pRenderTarget2); assert(hResult == S_OK);
    hResult = g_pEffect2->SetTexture("texture3", g_pRenderTarget3); assert(hResult == S_OK);
    hResult = g_pEffect2->SetBool("g_bEnableRayTracing", g_bRayTracingEnabled ? TRUE : FALSE);
    assert(hResult == S_OK);
    hResult = g_pEffect2->CommitChanges();                           assert(hResult == S_OK);

    DrawFullscreenQuad();

    hResult = g_pEffect2->EndPass(); assert(hResult == S_OK);
    hResult = g_pEffect2->End();     assert(hResult == S_OK);

    // === 追加: 左上に RT1 を 1/2 スケールで表示（D3DXSPRITE） ===
    if (false)
    {
        if (g_pSprite)
        {
            hResult = g_pSprite->Begin(D3DXSPRITE_ALPHABLEND);  assert(hResult == S_OK);

            D3DXMATRIX mat;
            D3DXVECTOR2 scaling(0.5f, 0.5f);     // 半分
            D3DXVECTOR2 trans(0.0f, 0.0f);       // 左上
            D3DXMatrixTransformation2D(&mat, NULL, 0.0f, &scaling, NULL, 0.0f, &trans);
            g_pSprite->SetTransform(&mat);

            // そのまま (0,0) へ描画
            hResult = g_pSprite->Draw(g_pRenderTarget2, NULL, NULL, NULL, 0xFFFFFFFF);
            assert(hResult == S_OK);

            hResult = g_pSprite->End(); assert(hResult == S_OK);
        }
    }

    hResult = g_pd3dDevice->EndScene();  assert(hResult == S_OK);

    hResult = g_pd3dDevice->SetRenderState(D3DRS_ZENABLE, TRUE);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->SetRenderTarget(0, pOldRT0);
    assert(hResult == S_OK);

    SAFE_RELEASE(pRT0);
    SAFE_RELEASE(pOldRT0);
}

void RenderPass3()
{
    HRESULT hResult = E_FAIL;

    hResult = g_pd3dDevice->Clear(0, NULL,
                                  D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER,
                                  D3DCOLOR_XRGB(0, 0, 0),
                                  1.0f, 0);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->SetRenderState(D3DRS_ZENABLE, FALSE);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->BeginScene();
    assert(hResult == S_OK);

    hResult = g_pEffect3->SetTechnique("Technique1");
    assert(hResult == S_OK);

    UINT numPass = 0;
    hResult = g_pEffect3->Begin(&numPass, 0);
    assert(hResult == S_OK);
    hResult = g_pEffect3->BeginPass(0);
    assert(hResult == S_OK);

    hResult = g_pEffect3->SetTexture("texture1", g_pRenderTarget4);
    assert(hResult == S_OK);
    hResult = g_pEffect3->SetTexture("texture2", g_pRenderTarget2);
    assert(hResult == S_OK);
    hResult = g_pEffect3->SetTexture("texture3", g_pRenderTarget3);
    assert(hResult == S_OK);
    hResult = g_pEffect3->SetBool("g_bEnableSSAO", g_bSSAOEnabled ? TRUE : FALSE);
    assert(hResult == S_OK);
    hResult = g_pEffect3->CommitChanges();
    assert(hResult == S_OK);

    DrawFullscreenQuad();

    hResult = g_pEffect3->EndPass();
    assert(hResult == S_OK);
    hResult = g_pEffect3->End();
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->EndScene();
    assert(hResult == S_OK);
    hResult = g_pd3dDevice->Present(NULL, NULL, NULL, NULL);
    assert(hResult == S_OK);

    hResult = g_pd3dDevice->SetRenderState(D3DRS_ZENABLE, TRUE);
    assert(hResult == S_OK);
}

void DrawFullscreenQuad()
{
    QuadVertex v[4] { };

    v[0].x = -1.0f; v[0].y = -1.0f; v[0].z = 0.0f; v[0].w = 1.0f; v[0].u = 0.0f; v[0].v = 1.0f;
    v[1].x = -1.0f; v[1].y = 1.0f; v[1].z = 0.0f; v[1].w = 1.0f; v[1].u = 0.0f; v[1].v = 0.0f;
    v[2].x = 1.0f; v[2].y = -1.0f; v[2].z = 0.0f; v[2].w = 1.0f; v[2].u = 1.0f; v[2].v = 1.0f;
    v[3].x = 1.0f; v[3].y = 1.0f; v[3].z = 0.0f; v[3].w = 1.0f; v[3].u = 1.0f; v[3].v = 0.0f;

    g_pd3dDevice->SetVertexDeclaration(g_pQuadDecl);
    g_pd3dDevice->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, sizeof(QuadVertex));
}

LRESULT WINAPI MsgProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg)
    {
    case WM_DESTROY:
    {
        PostQuitMessage(0);
        g_bClose = true;
        return 0;
    }
    case WM_KEYDOWN:
    {
        if (wParam == '1')
        {
            g_bRayTracingEnabled = !g_bRayTracingEnabled;
            return 0;
        }
        if (wParam == '2')
        {
            g_bSSAOEnabled = !g_bSSAOEnabled;
            return 0;
        }
        break;
    }
    }
    return DefWindowProc(hWnd, msg, wParam, lParam);
}
