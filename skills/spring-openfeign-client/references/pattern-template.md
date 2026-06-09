# 代码模板

## Feign 接口

```java
@ConditionalOnProperty(name = "xxx.mock", havingValue = "false", matchIfMissing = true)
@FeignClient(name = "XxxClient", url = "${xxx.remote-url}", configuration = XxxFeignConfig.class)
public interface XxxClient {
    @PostMapping("/path/to/api")
    XxxResp someMethod(@RequestBody XxxReq req);
}
```

## Mock 实现

```java
@ConditionalOnProperty(name = "xxx.mock", havingValue = "true")
@Service
public class MockXxxClient implements XxxClient {
    @Override
    public XxxResp someMethod(XxxReq req) {
        return new XxxResp(/* 硬编码模拟数据 */);
    }
}
```

## 自定义 Decoder

```java
@Slf4j
@RequiredArgsConstructor
public class XxxFeignDecoder implements Decoder {
    private final ObjectMapper objectMapper;

    @Override
    public Object decode(Response response, Type type) throws IOException, FeignException {
        String bodyStr = Util.toString(response.body().asReader(StandardCharsets.UTF_8));
        JsonNode rootNode = objectMapper.readTree(bodyStr);
        int code = rootNode.get("statusCode").asInt(-1);
        if (code != 200) {
            throw new ServiceException("第三方服务调用异常");
        }
        JavaType parameterType = objectMapper.getTypeFactory().constructType(type);
        JavaType resultType = objectMapper.getTypeFactory()
                .constructParametricType(ApiResponse.class, parameterType);
        ApiResponse<?> result = objectMapper.readValue(bodyStr, resultType);
        return result.getData();
    }
}
```

## 响应泛型包装

> **重要**：必须用 `@JsonProperty` 对齐第三方 JSON key。即使 Java 字段名看起来与 JSON key 相同，第三方也常使用蛇形命名（如 `status_code`），不标注会导致反序列化得到 `null`。

```java
@Data
public class ApiResponse<T> {
    @JsonProperty("status_code")
    private Integer statusCode;

    @JsonProperty("message")
    private String message;

    @JsonProperty("timestamp")
    private String timestamp;

    @JsonProperty("data")
    private T data;
}
```

## 请求/响应 DTO

```java
@Data
public class XxxReq {
    @JsonProperty("remote_field_name")
    private String localFieldName;
}
```

## GET 请求与路径参数

```java
// GET 查询参数 — 使用 @SpringQueryMap 将 DTO 字段自动展开为 URL 参数
@GetMapping("/path/to/api")
XxxResp search(@SpringQueryMap XxxReq req);

// 路径参数
@GetMapping("/path/to/api/{id}")
XxxResp getById(@PathVariable("id") Long id);

// 表单提交
@PostMapping(value = "/path/to/api", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE)
XxxResp formSubmit(@RequestParam("name") String name);
```

## ErrorDecoder

> **必须实现**。Decoder 仅在 2xx 时调用；4xx/5xx 响应走 ErrorDecoder。不实现则抛出原始 `FeignException`。

```java
public class XxxErrorDecoder implements ErrorDecoder {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public Exception decode(String methodKey, Response response) {
        try {
            String bodyStr = Util.toString(response.body().asReader(StandardCharsets.UTF_8));
            JsonNode rootNode = objectMapper.readTree(bodyStr);
            String message = rootNode.has("message") ? rootNode.get("message").asText() : "第三方服务调用异常";
            return new ServiceException("[" + response.status() + "] " + message);
        } catch (IOException e) {
            return new ServiceException("[" + response.status() + "] 第三方服务异常，无法解析响应");
        }
    }
}
```

## Feign 配置类

> **不要加 `@Configuration` 注解**。加了会被 Component Scan 扫描到，变成影响所有 FeignClient 的全局配置。

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

## 认证模块（需要时）

### 认证专用 Feign Client

```java
@FeignClient(name = "AuthClient", url = "${xxx.remote-url}")
public interface AuthClient {
    @PostMapping("/auth/login")
    LoginRsp login(@RequestBody LoginReq loginReq);
}
```

### 登录请求/响应 DTO

```java
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class LoginReq {
    private String userName;
    private String password;
    // 如果第三方要求额外字段（如 isEncrypted、captcha 等），在此追加
}

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class LoginRsp {
    private Boolean success;
    private Integer code;
    private String message;
    private String data;  // data 即返回的 token 字符串
}
```

### RequestInterceptor

```java
@Slf4j
@RequiredArgsConstructor
public class AuthFeignInterceptor implements RequestInterceptor {

    @Value("${xxx.username}")
    private String username;
    @Value("${xxx.password}")
    private String password;
    @Value("${xxx.token-cache-ttl-ms:3300000}")
    private long tokenCacheTtlMs;

    private final AuthClient authClient;

    private volatile String cachedToken;
    private volatile long tokenExpireTime;

    @Override
    public void apply(RequestTemplate template) {
        String token = getOrRefreshToken();
        if (token == null) {
            throw new ServiceException("认证失败：无法获取 Token");
        }
        template.header("Authorization", "Bearer " + token);
    }

    private String getOrRefreshToken() {
        if (cachedToken != null && System.currentTimeMillis() < tokenExpireTime) {
            return cachedToken;
        }
        synchronized (this) {
            if (cachedToken != null && System.currentTimeMillis() < tokenExpireTime) {
                return cachedToken;
            }
            LoginRsp loginRsp = authClient.login(LoginReq.builder()
                    .userName(username)
                    .password(password)
                    .build());
            if (loginRsp != null
                    && Boolean.TRUE.equals(loginRsp.getSuccess())
                    && loginRsp.getCode() != null && loginRsp.getCode() == 200) {
                cachedToken = loginRsp.getData();
                tokenExpireTime = System.currentTimeMillis() + tokenCacheTtlMs;
                log.debug("Token 刷新成功");
                return cachedToken;
            }
            throw new ServiceException("认证失败：登录接口返回异常");
        }
    }
}
```

### 在业务 FeignClient 上注册拦截器

在 `XxxFeignConfig` 中通过 `@Bean` 注册拦截器（**FeignConfig 不能加 `@Configuration` 注解**，也不能直接在 `configuration` 属性中写拦截器实现类——那样不会被注册到 Feign 请求链中）：

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

    @Bean
    public AuthFeignInterceptor authFeignInterceptor(AuthClient authClient) {
        return new AuthFeignInterceptor(authClient);
    }
}
```

```java
@ConditionalOnProperty(name = "xxx.mock", havingValue = "false", matchIfMissing = true)
@FeignClient(
    name = "XxxClient",
    url = "${xxx.remote-url}",
    configuration = XxxFeignConfig.class
)
public interface XxxClient { ... }
```

## 配置示例

```yaml
xxx:
  remote-url: https://api.third-party.com
  mock: true                                 # true=Mock, false=真实调用
  username: ${THIRD_PARTY_USERNAME}          # 认证用户名（环境变量注入）
  password: ${THIRD_PARTY_PASSWORD}          # 认证密码（环境变量注入）
  token-cache-ttl-ms: 3300000               # Token 缓存有效期（毫秒），默认 55 分钟
```
