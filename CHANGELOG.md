## v3.0-beta.11
1. 修复透明页面背景是前一个Container的问题
2. 重写BoostContainerWidget判等方法，避免框架层对已存在页面进行rebuild

## v3.0-beta.10
1. BoostContainer重构，修复容器内打开和关闭页面时界面不刷新问题

## v3.0-beta.9
1. 添加前台后台的回调接口
2. 增加从原生open flutter页面时，open操作完成后的回调能力

Breaking Change:
 [iOS] 增加从原生open flutter页面时，open操作完成后的回调能力 : https://github.com/alibaba/flutter_boost/commit/7f55728955b0afcdbaba5a17543e9dbdf1c24e65
由于一些业务方需要知道页面动画是否完成，需要获取present的completion回调，
因此将
- (void) pushFlutterRoute:(NSString *) pageName uniqueId:(NSString *)uniqueId arguments:(NSDictionary *) arguments
改为
- (void) pushFlutterRoute:(NSString *) pageName uniqueId:(NSString *)uniqueId arguments:(NSDictionary *) arguments completion:(void(^)(BOOL)) completion;

## v3.0-beta.8
1. 提供flutter_boost.dart作为对外接口
2. BoostNavigator相关API和实现的修改
3. 解决_pendingResult可能没有完成的问题
4. 新增前置拦截器能力
5. 解决在push和pop的时候，页面栈所有页面重复build的问题
6. 使用effective_dart包提供的linter规则文件

## v3.0-beta.7
1. 生命周期实现调整
2. 解决Android端特定场景下生命周期事件重复的问题
3. 添加自定义启动参数设置入口
4. 新增页面回退传参能力

Breaking Change:
page create and destroy event adjustment : https://github.com/alibaba/flutter_boost/commit/62c88805bf08606805e13254170691d2bc00bd4a
由于生命周期实现的改变，PageVisiblityObserver的onPageShow和onPageHide方法中，不再包含参数isForegroundEvent以及isBackgroundEvent

## 1.12.13+2
  Fixed bugs

## 1.12.13
  Supported Flutter sdk 1.12.13

## 1.9.1+2

  Rename the version number and start supporting androidx by default, Based on the flutter 1.9.1 - hotfixs。
  fixed bugs

## 0.1.66

  Fixed bugs

## 0.1.64

  Fixed bugs

## 0.1.63

  android:
  Fixed bugs

  iOS:
  no change

## 0.1.61

  android:
  Fixed bugs

  iOS:
  no change

## 0.1.60

A better implementation to support Flutter v1.9.1+hotfixes

Change the content
android:

1. based on the v1.9.1+hotfixes branch of flutter
2. Solve major bugs, such as page parameter passing
3. Support platformview
4. Support androidx branch :feature/flutter_1.9_androidx_upgrade
5. Resolve memory leaks
6. Rewrite part of the code
7. API changes
8. Improved demo and added many demo cases

ios:

1.based on the v1.9.1+hotfixes branch of flutter
2.bugfixed



## 0.1.5
The main changes are as following:
1. The new version do the page jump (URL route) based on the inherited FlutterViewController or Activity. The jump procedure will create new instance of FlutterView, while the old version just reuse the underlying FlutterView
2. Avoiding keeping and reusing the FlutterView, there is no screenshot and complex attach&detach logical any more. As a result, memory is saved and black or white-screen issue occured in old version all are solved.
3. This version also solved the app life cycle observation issue, we recommend you to use ContainerLifeCycle observer to listen the app enter background or foreground notification instead of WidgetBinding.
4. We did some code refactoring, the main logic became more straightforward.

## 0.0.1

* TODO: Describe initial release.


### API changes
From the point of API changes, we did some refactoring as following:
#### iOS API changes
1. FlutterBoostPlugin's startFlutterWithPlatform function change its parameter from FlutterViewController to Engine
2. 
**Before change**
```objectivec
FlutterBoostPlugin
- (void)startFlutterWithPlatform:(id<FLBPlatform>)platform onStart:(void (^)(FlutterViewController *))callback;
```

**After change**

```objectivec
FlutterBoostPlugin2
- (void)startFlutterWithPlatform:(id<FLB2Platform>)platform
                         onStart:(void (^)(id<FlutterBinaryMessenger,
                                           FlutterTextureRegistry,
                                           FlutterPluginRegistry> engine))callback;

```

2. FLBPlatform protocol removed flutterCanPop、accessibilityEnable and added entryForDart
**Before change:**
```objectivec
@protocol FLBPlatform <NSObject>
@optional
//Whether to enable accessibility support. Default value is Yes.
- (BOOL)accessibilityEnable;
// flutter模块是否还可以pop
- (void)flutterCanPop:(BOOL)canpop;
@required
- (void)openPage:(NSString *)name
          params:(NSDictionary *)params
        animated:(BOOL)animated
      completion:(void (^)(BOOL finished))completion;
- (void)closePage:(NSString *)uid
         animated:(BOOL)animated
           params:(NSDictionary *)params
       completion:(void (^)(BOOL finished))completion;
@end
```
**After change:**
```objectivec
@protocol FLB2Platform <NSObject>
@optional
- (NSString *)entryForDart;
    
@required
- (void)open:(NSString *)url
   urlParams:(NSDictionary *)urlParams
        exts:(NSDictionary *)exts
      completion:(void (^)(BOOL finished))completion;
- (void)close:(NSString *)uid
       result:(NSDictionary *)result
         exts:(NSDictionary *)exts
   completion:(void (^)(BOOL finished))completion;
@end
```

#### Android API changes
Android mainly changed the IPlatform interface and its implementation.
It removed following APIs:
```java
Activity getMainActivity();
boolean startActivity(Context context,String url,int requestCode);
Map getSettings();
```

And added following APIs:

```java
void registerPlugins(PluginRegistry registry) 方法
void openContainer(Context context,String url,Map<String,Object> urlParams,int requestCode,Map<String,Object> exts);
void closeContainer(IContainerRecord record, Map<String,Object> result, Map<String,Object> exts);
IFlutterEngineProvider engineProvider();
int whenEngineStart();
```
