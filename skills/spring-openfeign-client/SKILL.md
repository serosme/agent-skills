---
name: spring-openfeign-client
description: 基于 Spring Cloud OpenFeign 封装第三方 HTTP API，实现统一响应解包、Mock 切换、异常处理、认证拦截。当用户需要对接第三方 REST 接口、封装远程调用时使用。
---

# spring-openfeign-client

基于 Spring Cloud OpenFeign 封装第三方 HTTP API，实现远程调用与本地 Bean 调用无差别化。完整代码模板参见 [references/pattern-template.md](references/pattern-template.md)。

## 前置条件

启动类加 `@EnableFeignClients(basePackages = "com.example.client")`。

## 核心步骤

### 1. 目录结构

```text
client/{service-name}/
├── {ServiceName}Client.java          ← Feign 接口
├── Mock{ServiceName}Client.java      ← Mock 实现
├── {ServiceName}FeignConfig.java     ← Feign 配置（Decoder/ErrorDecoder/Interceptor）
├── {ServiceName}FeignDecoder.java    ← 自定义 Decoder（处理 2xx 响应解包）
├── {ServiceName}ErrorDecoder.java    ← 自定义 ErrorDecoder（必须实现，处理 4xx/5xx）
├── auth/                             ← 认证模块（可选）
│   ├── AuthClient.java
│   ├── AuthFeignInterceptor.java
│   ├── LoginReq.java
│   └── LoginRsp.java
├── req/
└── resp/
```

### 2. ApiResponse 响应包装

根据第三方 JSON 信封结构创建 `resp/ApiResponse<T>`，**必须用 `@JsonProperty` 对齐第三方 JSON key**（第三方常用蛇形命名），泛型 `T` 对应 `data` 字段。

### 3. DTO

- `req/` 和 `resp/` 下分别定义请求/响应 DTO
- 用 `@JsonProperty` 映射驼峰 ↔ 蛇形命名，推荐 `@Data`

### 4. 自定义 Decoder

实现 `feign.codec.Decoder`（仅 2xx 时触发）：读 Body → 校验状态码 → 反序列化为 `ApiResponse<T>` → 只返回 `data`，调用方零感知信封。

### 5. ErrorDecoder（必须）

实现 `feign.codec.ErrorDecoder`，处理 4xx/5xx：读 Body → 解析错误信息 → 抛 `ServiceException`。**必须实现**，否则非 2xx 抛原始 `FeignException`。

### 6. Feign 配置类

> **不要加 `@Configuration`**，否则被 Component Scan 扫到会变成影响所有 FeignClient 的全局配置。

```java
public class XxxFeignConfig {
    @Bean
    public Decoder xxxFeignDecoder(ObjectMapper objectMapper) {
        return new XxxFeignDecoder(objectMapper);
    }

    @Bean
    public ErrorDecoder xxxErrorDecoder() {
        return new XxxErrorDecoder();
    }
}
```

### 7. Feign 接口

```java
@ConditionalOnProperty(name = "xxx.mock", havingValue = "false", matchIfMissing = true)
@FeignClient(name = "XxxClient", url = "${xxx.remote-url}", configuration = XxxFeignConfig.class)
public interface XxxClient {
    @PostMapping("/path/to/api")
    XxxResp someMethod(@RequestBody XxxReq req);
}
```

约束：

- **不要**额外加 `@Service`/`@Component`，`@FeignClient` 本身创建代理 Bean
- Mock 互斥：`@ConditionalOnProperty` — Client 设 `havingValue="false", matchIfMissing=true`，Mock 设 `havingValue="true"`
- `url` 从配置读取，不硬编码
- 返回类型直接写业务 DTO，Decoder 自动解包
- **不同服务的 `@FeignClient` 必须用不同的 `name`**

> 如 `@ConditionalOnProperty` 不生效（极旧版本），可用 `@Profile("!mock")` / `@Profile("mock")` 替代。

### 8. Mock 实现

```java
@ConditionalOnProperty(name = "xxx.mock", havingValue = "true")
@Service
public class MockXxxClient implements XxxClient { /* 返回模拟数据 */ }
```

### 9. 认证（可选）

当第三方需认证时，创建 `auth/` 子包：

- **AuthClient** — 独立 Feign 接口，**不注册认证拦截器**（避免循环依赖）
- **AuthFeignInterceptor** — `RequestInterceptor`，`volatile` + `synchronized` 双重检查缓存 Token，用户名/密码/缓存 TTL 通过 `@Value` 注入
- 在 `XxxFeignConfig` 中注册拦截器 Bean

其他认证方式：固定 API Key（直接注入 Header）、OAuth2 Client Credentials、HMAC 签名、Cookie/Session。

### 10. 配置项

```yaml
xxx:
  remote-url: https://api.third-party.com
  mock: true
  username: ${THIRD_PARTY_USERNAME}
  password: ${THIRD_PARTY_PASSWORD}
  token-cache-ttl-ms: 3300000

spring.cloud.openfeign.client.config.default:
  connectTimeout: 5000
  readTimeout: 30000
  loggerLevel: BASIC

logging.level.com.example.client: DEBUG
```

### 11. 依赖

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-openfeign</artifactId>
</dependency>
<dependency>
    <groupId>io.github.openfeign</groupId>
    <artifactId>feign-httpclient</artifactId>
</dependency>
```

### 12. 其他请求模式

| 场景         | 注解                         | 示例                                                           |
| ------------ | ---------------------------- | -------------------------------------------------------------- |
| GET 查询参数 | `@SpringQueryMap`            | `XxxResp search(@SpringQueryMap XxxReq req)`                   |
| 路径参数     | `@PathVariable`              | `XxxResp getById(@PathVariable("id") Long id)`                 |
| 表单提交     | `@RequestParam` + `consumes` | `@PostMapping(consumes = "application/x-www-form-urlencoded")` |

## 验证清单

| #   | 检查项            | 说明                                                                 |
| --- | ----------------- | -------------------------------------------------------------------- |
| 1   | 接口契约化        | `@FeignClient` 注入为 Spring Bean                                    |
| 2   | Mock 开关         | `@ConditionalOnProperty` 互斥                                        |
| 3   | Decoder 解包      | 业务层只接收纯 DTO                                                   |
| 4   | ErrorDecoder 实现 | 非 2xx 抛 `ServiceException`，不泄露 `FeignException`                |
| 5   | DTO 映射          | `@JsonProperty` 解决命名差异（含 ApiResponse 自身）                  |
| 6   | FeignConfig 隔离  | **未**标注 `@Configuration`                                          |
| 7   | Client name 唯一  | 不同服务不同 `name`                                                  |
| 8   | 认证拦截（可选）  | AuthClient 不注册拦截器，Token 本地缓存，拦截器通过 FeignConfig 注册 |
| 9   | 超时与日志已配置  | connectTimeout/readTimeout/loggerLevel 已设                          |
