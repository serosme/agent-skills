# 注册流程示例

一个完整的三步写操作，从请求类型到 Service 调用方一次性写全，用来对照落地。

规则以 [../SKILL.md](../SKILL.md) 与 [pattern-template.md](pattern-template.md) 为准；
本文件只做演示，不单独承载通用规则。它假设领域异常是未检查异常，以便事务失败时回滚。

## 场景与步骤

用户提交注册：用户名和密码。流程要求：

1. 校验并规范化用户名；用户名已存在则拒绝注册。
2. 为密码生成随机盐并计算 SM3 摘要；明文密码不得入库。
3. 保存用户记录并返回用户 ID。

| 顺序 | 常量                         | Handler                           | 条件       | 传递结果       |
| ---- | ---------------------------- | --------------------------------- | ---------- | -------------- |
| 10   | `REGISTER_USERNAME_VALIDATE` | `RegisterUsernameValidateHandler` | 无         | 规范化用户名   |
| 20   | `REGISTER_PASSWORD_HASH`     | `RegisterPasswordHashHandler`     | 用户名可用 | 盐值、密码摘要 |
| 30   | `REGISTER_SAVE`              | `RegisterSaveHandler`             | 前两步完成 | `RegisterResp` |

## 示例假设

这些类和方法是示例契约；目标项目需映射到实际类型及 API。Repository 示例假设支持 JPA 风格的显式 `saveAndFlush`：

- `me.cloud.shared.processor.Processor` / `Context` / `Handler`，源码见 [pattern-template.md](pattern-template.md)。
- `me.cloud.shared.exception.BizException` 是项目统一的未检查业务异常（继承 `RuntimeException`），提供 `(String)` 与 `(String, Throwable)` 构造器。
- 示例使用 Java 17+ 的 `record` 语法；较低 Java 版本应替换为项目 DTO 写法。
- `me.cloud.shared.util.PasswordUtil`：`generateSalt()` 生成随机盐；`sm3Hash(明文, 盐)` 返回摘要。参考项目使用随机盐配合 Hutool SM3 摘要；实际实现的随机源、盐长度、字符编码和摘要格式均应按项目安全规范核验，不以方法名推断安全强度。
- `me.cloud.dao.entity.UserEntity` 保存规范化用户名、盐值、密码摘要和创建时间。
- `me.cloud.dao.repository.UserRepository` 提供 `existsByUsername` 与 `saveAndFlush`；成功后实体含生成的 ID。数据库对存储的规范化用户名有唯一约束；Repository 在 `saveAndFlush` 阶段识别该约束冲突并抛 `DuplicateUsernameException`，其他完整性异常不转换为此异常。
- 本例按 `trim()` 规范化用户名；大小写及 Unicode 规范化需由项目规则明确，并与查重、持久化及唯一约束一致。数据库列和唯一索引必须针对与查重相同的规范化值；如果 `saveAndFlush` 在外层事务代理提交阶段才抛冲突，不能在同一事务方法内捕获后继续使用该事务，应在合适边界映射异常。

`DuplicateUsernameException` 是示例中的领域异常，由 Repository 适配层在 `saveAndFlush` 阶段按目标数据库识别用户名唯一约束冲突后抛出：

```java
package me.cloud.dao.exception;

public final class DuplicateUsernameException extends RuntimeException {
    public DuplicateUsernameException(Throwable cause) {
        super(cause);
    }
}
```

## 请求与响应

Web 入口使用 `@Valid` 触发请求校验；Handler 仍检查关键值，避免内部调用绕过入口校验。

```java
package me.cloud.system.controller.req;

import jakarta.validation.constraints.NotBlank;

public record RegisterReq(
        @NotBlank String username,
        @NotBlank String password
) {
}
```

```java
package me.cloud.system.controller.resp;

public record RegisterResp(Long userId) {
}
```

## Context

规范化用户名、盐值和密码摘要是步骤间传递的数据，放在 `Context` 字段中。

```java
package me.cloud.system.processor.register;

import me.cloud.shared.processor.Context;
import me.cloud.system.controller.req.RegisterReq;
import me.cloud.system.controller.resp.RegisterResp;
import me.cloud.system.processor.register.handler.RegisterPasswordHashHandler;
import me.cloud.system.processor.register.handler.RegisterSaveHandler;
import me.cloud.system.processor.register.handler.RegisterUsernameValidateHandler;
import lombok.Data;
import lombok.EqualsAndHashCode;

@Data
@EqualsAndHashCode(callSuper = true)
public class RegisterContext extends Context<RegisterReq, RegisterResp> {
    /**
     * 校验并规范化用户名
     * <p>条件：无</p>
     * <p>输入：{@link RegisterReq#username()}</p>
     * <p>过程：拒绝空用户名；按约定规范化后检查是否已存在</p>
     * <p>输出：规范化后的用户名</p>
     *
     * @see RegisterUsernameValidateHandler
     */
    public static final int REGISTER_USERNAME_VALIDATE = 10;

    /**
     * 处理密码
     * <p>条件：用户名可用</p>
     * <p>输入：{@link RegisterReq#password()}</p>
     * <p>过程：生成随机盐并计算密码摘要</p>
     * <p>输出：盐值、密码摘要</p>
     *
     * @see RegisterPasswordHashHandler
     */
    public static final int REGISTER_PASSWORD_HASH = 20;

    /**
     * 入库
     * <p>条件：用户名校验与密码处理完成</p>
     * <p>输入：规范化后的用户名、盐值、密码摘要</p>
     * <p>过程：保存用户记录，不保存明文密码</p>
     * <p>输出：{@link RegisterResp}</p>
     *
     * @see RegisterSaveHandler
     */
    public static final int REGISTER_SAVE = 30;

    private String normalizedUsername;
    private String salt;
    private String passwordHash;
}
```

## 步骤 10：校验并规范化用户名

```java
package me.cloud.system.processor.register.handler;

import me.cloud.dao.repository.UserRepository;
import me.cloud.shared.exception.BizException;
import me.cloud.shared.processor.Handler;
import me.cloud.system.processor.register.RegisterContext;
import lombok.RequiredArgsConstructor;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

@RequiredArgsConstructor
@Order(RegisterContext.REGISTER_USERNAME_VALIDATE)
@Service
public class RegisterUsernameValidateHandler implements Handler<RegisterContext> {
    private final UserRepository userRepository;

    @Override
    public void handle(RegisterContext context) {
        String username = context.getIn().username();
        if (username == null || username.isBlank()) {
            throw new BizException("用户名不能为空");
        }

        String normalizedUsername = username.trim();
        if (userRepository.existsByUsername(normalizedUsername)) {
            throw new BizException("用户名已存在");
        }

        context.setNormalizedUsername(normalizedUsername);
    }
}
```

## 步骤 20：处理密码

本例按请求指定演示 SM3 加盐摘要；术语上这是**哈希/摘要，不是加密**。盐值与摘要写入 `Context`，供入库步骤取用。参考项目的 `PasswordUtil` 也采用 SM3 加盐摘要，因此保留为贴近该参考用法的演示；它是快速哈希，不能据此视为推荐的生产密码存储方案。

```java
package me.cloud.system.processor.register.handler;

import me.cloud.shared.exception.BizException;
import me.cloud.shared.processor.Handler;
import me.cloud.shared.util.PasswordUtil;
import me.cloud.system.processor.register.RegisterContext;
import lombok.RequiredArgsConstructor;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

@RequiredArgsConstructor
@Order(RegisterContext.REGISTER_PASSWORD_HASH)
@Service
public class RegisterPasswordHashHandler implements Handler<RegisterContext> {

    @Override
    public void handle(RegisterContext context) {
        String rawPassword = context.getIn().password();
        if (rawPassword == null || rawPassword.isBlank()) {
            throw new BizException("密码不能为空");
        }

        String salt = PasswordUtil.generateSalt();
        String passwordHash = PasswordUtil.sm3Hash(rawPassword, salt);

        context.setSalt(salt);
        context.setPasswordHash(passwordHash);
    }
}
```

## 步骤 30：入库并产出响应

入库前检查前序步骤产物，避免缺少 Handler 或步骤数据时仍保存不完整记录。

```java
package me.cloud.system.processor.register.handler;

import me.cloud.dao.entity.UserEntity;
import me.cloud.dao.exception.DuplicateUsernameException;
import me.cloud.dao.repository.UserRepository;
import me.cloud.shared.exception.BizException;
import me.cloud.shared.processor.Handler;
import me.cloud.system.controller.resp.RegisterResp;
import me.cloud.system.processor.register.RegisterContext;
import lombok.RequiredArgsConstructor;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

@RequiredArgsConstructor
@Order(RegisterContext.REGISTER_SAVE)
@Service
public class RegisterSaveHandler implements Handler<RegisterContext> {
    private final UserRepository userRepository;

    @Override
    public void handle(RegisterContext context) {
        if (context.getNormalizedUsername() == null
                || context.getSalt() == null
                || context.getPasswordHash() == null) {
            throw new IllegalStateException("注册前置步骤未完成");
        }

        UserEntity user = UserEntity.builder()
                .username(context.getNormalizedUsername())
                .salt(context.getSalt())
                .passwordHash(context.getPasswordHash())
                .createTime(LocalDateTime.now())
                .build();
        try {
            userRepository.saveAndFlush(user);
        } catch (DuplicateUsernameException ex) {
            throw new BizException("用户名已存在", ex);
        }

        context.setOut(new RegisterResp(user.getId()));
    }
}
```

## 调用方

三个步骤在同一个 Service 事务中执行；Handler 不各自开启事务。

```java
package me.cloud.system.service;

import me.cloud.shared.processor.Processor;
import me.cloud.system.controller.req.RegisterReq;
import me.cloud.system.controller.resp.RegisterResp;
import me.cloud.system.processor.register.RegisterContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@RequiredArgsConstructor
@Service
public class RegisterService {
    private final Processor processor;

    @Transactional
    public RegisterResp register(RegisterReq req) {
        RegisterContext context = new RegisterContext();
        context.setIn(req);
        processor.process(context);

        RegisterResp response = context.getOut();
        if (response == null) {
            throw new IllegalStateException("注册流程未生成响应");
        }
        return response;
    }
}
```

## 并发与安全边界

- 存在性查询只用于尽早返回友好错误，不能防止两个并发请求同时通过查询。数据库必须对规范化后的用户名建立唯一约束；`saveAndFlush` 暴露该约束冲突后映射为用户名已存在。只转换用户名约束冲突，不把所有完整性错误都改写为用户名冲突。`saveAndFlush` 适用于 JPA 风格的 Repository；若目标持久化层在提交阶段才暴露唯一冲突，应在事务边界捕获并映射，不能假设 `save` 当场抛出。
- `trim()` 是本例选定的规范化规则，不代表适用于所有产品。大小写、Unicode 规范化与数据库排序规则必须一致，并与查重及唯一约束使用同一规范化值。
- SM3 是快速哈希；加盐不能让它变成慢哈希，也不能阻止高速离线猜测。生产系统应按安全规范评估 Argon2id、bcrypt、PBKDF2 等专用密码哈希方案。只有安全要求明确接受时才沿用 SM3，不把本例算法当成默认最佳实践。不要把包含明文密码的 Request/Context 输出到日志，尤其避免直接记录 record 的 `toString()`。
- 本三步流程没有外部副作用。若将来增加短信、邮件等通知，应先确认通知失败是否影响注册；通常在事务提交后处理，或使用 Outbox 等可靠事件方案，避免数据库回滚与外部通知状态不一致。
- 最小化密码明文生命周期：不要把原始密码复制到 `Context` 字段或额外对象；SM3 如被明确要求使用，应确认摘要算法的输入编码与格式符合安全规范。

## 调用链与验收

一次成功调用按 `@Order` 执行 10 → 20 → 30：校验步骤写 `normalizedUsername`，密码步骤写 `salt` 与 `passwordHash`，入库步骤复用这些字段并写 `out`，Service 返回响应。任一步抛未检查异常即停止后续 Handler，并使 Service 事务回滚数据库操作。若项目使用检查型异常，需配置相应的 `rollbackFor`。

核对项：

- 三个 Handler 都是 `Handler<RegisterContext>` Bean，且分别引用 Context 中的顺序常量。
- `RegisterSaveHandler` 拒绝缺失的前序结果；Service 检查响应非空；在目标项目中通过启动检查或测试确认框架确实发现三个 Handler。
- 明文密码从未写入实体或日志；不要直接记录包含密码的 Request/Context（如 record 的 `toString()`）；数据库唯一约束保护并发注册。
- 本示例是说明 Processor 编排的静态代码示例，不等同于已在具体项目编译、测试或安全审查。
