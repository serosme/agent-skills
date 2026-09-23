# Processor 编排模板

`Processor` + `Context` + `Handler` 的框架源码、各类文件的骨架模板与命名顺序约定。
本文件保持领域无关，只回答「每类文件长什么样」。

需要一份完整流程示例时，读取 [examples.md](examples.md)。
模板中的 `Xxx` 是占位符，代码骨架中的类型和方法需替换为项目实际定义，不保证可直接编译。

## 框架三件套

三个类放在公共模块的 `shared/processor` 包下。仓库已有这三个类时直接使用，不要重建；
仓库缺少时才按本节源码创建，并确认该包在组件扫描范围内。

本节源码与后续模板统一以 `me.cloud` 为根包名；目标仓库的根包名不同时按实际包名替换。以下代码是结构骨架，示例类型、字段与 Repository 方法需按项目定义替换，不保证可直接编译。

### Context

```java
package me.cloud.shared.processor;

import lombok.Data;

@Data
public class Context<I, O> {
    private I in;
    private O out;
}
```

### Handler

```java
package me.cloud.shared.processor;

public interface Handler<C extends Context<?, ?>> {
    default boolean shouldHandle(C context) {
        return true;
    }

    void handle(C context);
}
```

### Processor

```java
package me.cloud.shared.processor;

import org.springframework.context.ApplicationContext;
import org.springframework.core.ResolvableType;
import org.springframework.core.annotation.AnnotationAwareOrderComparator;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

@Component
public class Processor {
    private final ApplicationContext applicationContext;

    public Processor(ApplicationContext applicationContext) {
        this.applicationContext = applicationContext;
    }

    @SuppressWarnings("unchecked")
    public <C extends Context<?, ?>> void process(C context) {
        Class<C> type = (Class<C>) context.getClass();
        ResolvableType resolvableType = ResolvableType.forClassWithGenerics(Handler.class, type);

        List<Handler<C>> handlers = new ArrayList<>();
        for (String name : applicationContext.getBeanNamesForType(resolvableType)) {
            handlers.add((Handler<C>) applicationContext.getBean(name));
        }
        AnnotationAwareOrderComparator.sort(handlers);

        for (Handler<C> handler : handlers) {
            if (handler.shouldHandle(context)) {
                handler.handle(context);
            }
        }
    }
}
```

### 框架实现与约定边界

- 泛型匹配以传入 `context` 的运行时类型构造 `ResolvableType`，目标是对应的 `Handler<ConcreteContext>`；Handler 应声明具体 Context 类型，并在目标 Spring 版本验证 Bean 匹配与发现结果。
- 框架不会校验是否覆盖完整步骤；若没有 Handler，`process` 会空跑。调用方检查响应非空只能发现部分漏配；还应在启动检查或测试中确认该 Context 的全部预期 Handler 都已注册，不能把空流程当作成功。
- 执行顺序由 `AnnotationAwareOrderComparator` 对 `@Order` 排序得出，Bean 的发现顺序不参与；本模式要求每个 Handler 显式标注 `@Order(Context.步骤常量)`，不依赖默认顺序或同值顺序。
- `shouldHandle` 默认返回 `true`，只在步骤有条件时重写。

## 目录结构

```text
processor/{操作名}/
├── {操作名}Context.java              ← 步骤常量 + 跨步骤中间结果字段
└── handler/
    ├── {操作名}ValidationHandler.java
    ├── {操作名}PermissionHandler.java
    ├── {操作名}Handler.java
    └── {操作名}ResponseHandler.java
```

- 一个业务操作一个 `processor/{操作名}` 包，包名用操作语义，多级用子包区分（如 `register`、`record/create`）。
- Handler 放在同级 `handler` 子包。
- 类名后缀跟随目标模块同包既有风格；若没有既有风格，统一采用项目约定，不混用 `...Handler` 与 `...HandlerImpl`。

## Context 模板

步骤常量按执行顺序声明，每步一段四段式 Javadoc：条件、输入、过程、输出，末尾用 `@see` 指向实现类。

```java
package me.cloud.system.processor.xxx;

import me.cloud.shared.processor.Context;
import me.cloud.system.controller.req.XxxReq;
import me.cloud.system.controller.resp.XxxResp;
import me.cloud.system.processor.xxx.handler.XxxProcessHandler;
import me.cloud.system.processor.xxx.handler.XxxSaveHandler;
import me.cloud.system.processor.xxx.handler.XxxValidateHandler;
import lombok.Data;
import lombok.EqualsAndHashCode;

@Data
@EqualsAndHashCode(callSuper = true)
public class XxxContext extends Context<XxxReq, XxxResp> {
    /**
     * 校验
     * <p>条件：无</p>
     * <p>输入：{@link XxxReq}</p>
     * <p>过程：校验入参是否允许本操作</p>
     * <p>输出：无</p>
     *
     * @see XxxValidateHandler
     */
    public static final int XXX_VALIDATE = 10;

    /**
     * 加工
     * <p>条件：校验通过</p>
     * <p>输入：{@link XxxReq}</p>
     * <p>过程：产出后续步骤要用的数据</p>
     * <p>输出：中间结果</p>
     *
     * @see XxxProcessHandler
     */
    public static final int XXX_PROCESS = 20;

    /**
     * 落库
     * <p>条件：加工完成</p>
     * <p>输入：{@link XxxReq}、上一步的中间结果</p>
     * <p>过程：保存记录</p>
     * <p>输出：{@link XxxResp}</p>
     *
     * @see XxxSaveHandler
     */
    public static final int XXX_SAVE = 30;

    private Long intermediate;
}
```

要点：

- 有额外字段时加 `@Data` 与 `@EqualsAndHashCode(callSuper = true)`；
  如果使用 `@AllArgsConstructor`，还需提供无参构造器，因为调用方要 `new XxxContext()`。
- 没有额外字段时不需要任何 Lombok 注解，类体只放步骤常量。
- 入参不是单一 DTO 时（如无入参操作），把对应泛型位置写成 `Void`，调用方不调用 `setIn`。
- 入参类型按入口实际使用的请求类声明；同一操作有多个入口时复用同一个请求类，
  用额外字段区分入口（如一个布尔标记字段加该入口对应的权限点字段）。

## Handler 模板

### 普通步骤

Handler 是 Spring Bean，标注 `@Order(XxxContext.步骤常量)`，泛型参数是该 `Context` 类本身；依赖注入注解（如 `@RequiredArgsConstructor`）沿用目标模块现有风格。
代码假设项目有统一业务异常 `BizException` 与 `XxxRepository`；实际类型按目标项目替换。

```java
package me.cloud.system.processor.xxx.handler;

import me.cloud.shared.exception.BizException;
import me.cloud.shared.processor.Handler;
import me.cloud.system.processor.xxx.XxxContext;
import lombok.RequiredArgsConstructor;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

@RequiredArgsConstructor
@Order(XxxContext.XXX_VALIDATE)
@Service
public class XxxValidateHandler implements Handler<XxxContext> {
    private final XxxRepository xxxRepository;

    @Override
    public void handle(XxxContext context) {
        var req = context.getIn();

        if (xxxRepository.existsByBusinessKey(req.businessKey())) {
            throw new BizException("记录已存在");
        }
    }
}
```

### 产出中间结果的步骤

写入 `Context` 的数据供后续步骤直接复用，后续步骤不要重新算一遍。具体请求字段以目标项目类型为准；代码行是类型匹配的结构示意。

```java
package me.cloud.system.processor.xxx.handler;

import me.cloud.shared.processor.Handler;
import me.cloud.system.processor.xxx.XxxContext;
import lombok.RequiredArgsConstructor;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

@RequiredArgsConstructor
@Order(XxxContext.XXX_PROCESS)
@Service
public class XxxProcessHandler implements Handler<XxxContext> {

    @Override
    public void handle(XxxContext context) {
        var req = context.getIn();

        // 示例仅演示跨步骤结果传递；实际业务逻辑按单步职责实现。
        // 若本步骤本身要持久化或执行外部操作，应作为独立业务步骤表达，明确其事务和失败语义。
        Long intermediate = req.targetId();
        context.setIntermediate(intermediate);
    }
}
```

### 条件步骤

条件步骤只在业务流程确实需要时添加，不是每个 `Context` 的必需结构。此时在对应 `Context` 中增加一个步骤常量和 Javadoc，并添加 Handler，例如使用空闲值 `XXX_CASCADE = 40`；不要照抄到没有该步骤的流程。

重写 `shouldHandle` 表示「这一步可以整体跳过」，条件只读 `Context`；不成立时 `handle` 完全不会执行。

```java
package me.cloud.system.processor.xxx.handler;

import me.cloud.shared.processor.Handler;
import me.cloud.system.processor.xxx.XxxContext;
import lombok.RequiredArgsConstructor;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

@RequiredArgsConstructor
@Order(XxxContext.XXX_CASCADE)
@Service
public class XxxCascadeHandler implements Handler<XxxContext> {
    private final XxxCascadeService xxxCascadeService;

    @Override
    public boolean shouldHandle(XxxContext context) {
        // 条件只读 Context：请求带了目标值才需要这一步
        return context.getIn().targetId() != null;
    }

    @Override
    public void handle(XxxContext context) {
        // 只有 shouldHandle 返回 true 时才会走到这里
        xxxCascadeService.cascade(context.getIn().targetId());
    }
}
```

`shouldHandle` 的使用边界：

- 只用于确实可选的步骤，例如值未变化时跳过派生更新、某资源类型不适用时跳过处理、步骤只对某入口生效。
- 不要因必需的前序数据缺失而跳过；此类情况应由 Handler 校验并失败，避免流程静默产出不完整结果。
- 条件只读 `Context`（存量实现均如此）：不查库、不发远程调用；该方法在 `handle` 前调用，应保持为快速、无副作用的判断。
- 不用于表达顺序依赖：依赖前序步骤结果的情况，用步骤顺序加前序步骤抛异常解决。

### 产出响应

业务响应由产出它的那一步写入，不必是最后一步；写入之后 `out` 就是一个可读的中间结果，
后续步骤可以直接取用，不要重写。以下片段假设响应为 `record XxxResp(Long id) {}`。

```java
// 产出响应的那一步写入 out
context.setOut(new XxxResp(context.getIntermediate()));
```

```java
// 排在其后的步骤可以直接读 out 里的中间结果继续加工，不重写 out
Long id = context.getOut().id();
```

## 调用方模板

Service 注入 `Processor`，方法体只保留入参、编排、检查结果与返回。需要原子性的多步数据库写入时，在该入口管理事务；Handler 通常不各自开启事务。短信、邮件等外部副作用不要未经设计直接纳入数据库事务。

```java
@RequiredArgsConstructor
@Service
public class XxxService {
    private final Processor processor;

    // 需要原子性的多步数据库写入时，在此 Service 方法上添加 @Transactional
    public XxxResp handle(XxxReq req) {
        XxxContext context = new XxxContext();
        context.setIn(req);
        processor.process(context);

        XxxResp response = context.getOut();
        if (response == null) {
            throw new IllegalStateException("流程未生成响应");
        }
        return response;
    }
}
```

入参不是单一 DTO 时，在 `process` 前直接设置 `Context` 字段：

```java
XxxQueryContext context = new XxxQueryContext();
context.setTargetId(targetId);
processor.process(context);
return context.getOut();
```

## 顺序与命名约定

| 项           | 约定                                                                                |
| ------------ | ----------------------------------------------------------------------------------- |
| 顺序常量     | `Context` 上的 `public static final int`，按执行顺序声明                            |
| 顺序取值     | 步长 10（10、20、30…）；插队取中间值（如 5、15）；不复用已有取值                    |
| 顺序引用     | 只在 `@Order(XxxContext.常量)` 中引用，不写字面量                                   |
| 步骤 Javadoc | 条件 / 输入 / 过程 / 输出 四段，末尾 `@see` 实现类                                  |
| Handler 注解 | Spring Bean + `@Order(...)`；构造器注入方式沿用目标模块风格                         |
| 请求响应类型 | 优先用 `record`；仓库使用 Lombok 建造器类时沿用 `.builder()...build()`              |
| 事务         | 按原子性需求由 Service 调用入口划界；Handler 不擅自开启独立事务；外部副作用单独设计 |
| 步骤命名     | `...ValidationHandler`、`...PermissionHandler`、`...QueryHandler`、`...Handler`     |
