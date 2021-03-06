/*******************************************************************************
 *
 * MIT License
 *
 * Copyright (c) 2017 Advanced Micro Devices, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 *******************************************************************************/

#include "args.hpp"
#include "get_handle.hpp"
#include "network_data.hpp"
#include "tensor_holder.hpp"
#include "test.hpp"
#include "verify.hpp"

#include <functional>
#include <deque>
#include <half.hpp>
#include <type_traits>
#include <miopen/functional.hpp>
#include <miopen/type_name.hpp>

template <class U, class T>
constexpr std::is_same<T, U> is_same(const T&)
{
    return {};
}

struct rand_gen
{
    unsigned long max_value = 17;
    template <class... Ts>
    double operator()(Ts... Xs) const
    {
        static_assert(sizeof...(Ts) < 6, "Dimensions in rand_gen must be less than 6.");
        assert(max_value > 0);
        std::array<unsigned long, sizeof...(Ts)> left = {{Xs...}};
        std::array<unsigned long, 5> right            = {{613, 547, 701, 877, 1049}};
        unsigned long dot = std::inner_product(left.begin(), left.end(), right.begin(), 173ul);
        return double(dot % max_value);
    };
};

// Run cpu in parallel if it can be ran as const
template <class V, class... Ts>
auto cpu_async(const V& v, Ts&&... xs) -> std::future<decltype(v.cpu(xs...))>
{
    return detach_async([&] { return v.cpu(xs...); });
}

template <class V, class... Ts>
auto cpu_async(V& v, Ts&&... xs) -> std::future<decltype(v.cpu(xs...))>
{
    return std::async(std::launch::deferred, [&] { return v.cpu(xs...); });
}

struct test_driver
{
    test_driver()                   = default;
    test_driver(const test_driver&) = delete;
    test_driver& operator=(const test_driver&) = delete;

    struct argument
    {
        std::function<void(std::vector<std::string>)> write_value;
        std::function<std::string()> read_value;
        std::vector<std::function<void()>> post_write_actions;
        std::vector<std::function<void(std::function<void()>)>> data_sources;
        std::string type;
        std::string name;

        // Function may refer to the argument by reference so this needs to be noncopyable
        argument()                = default;
        argument(const argument&) = delete;
        argument& operator=(const argument&) = delete;

        void post_write()
        {
            for(const auto& pw : post_write_actions)
            {
                pw();
            }
        }
        void write(std::vector<std::string> c)
        {
            write_value(c);
            post_write();
        }

        template <class Source, class T>
        void add_source(Source src, T& x)
        {
            data_sources.push_back([=, &x](std::function<void()> callback) {
                for(auto y : src()) // NOLINT
                {
                    x = T(y);
                    post_write();
                    callback();
                }

            });
        }
    };

    std::string program_name;
    std::deque<argument> arguments;
    std::unordered_map<std::string, std::size_t> argument_index;
    miopenDataType_t type = miopenFloat;
    bool full_set         = false;
    bool verbose          = false;
    double tolerance      = 80;
    bool time             = false;
    int batch_factor      = 0;
    bool no_validate      = false;
    int repeat            = 1;
    bool rethrow          = false;

    argument& get_argument(const std::string& s)
    {
        assert(arguments.at(argument_index.at(s)).name == s);
        return arguments.at(argument_index.at(s));
    }

    bool has_argument(const std::string& arg) { return argument_index.count(arg) > 0; }

    template <class Visitor>
    void parse(Visitor v)
    {
        v(full_set, {"--all"}, "Run all tests");
        v(verbose, {"--verbose", "-v"}, "Run verbose mode");
        v(tolerance, {"--tolerance", "-t"}, "Set test tolerance");
        v(time, {"--time"}, "Time the kernel on GPU");
        v(batch_factor, {"--batch-factor", "-n"}, "Set batch factor");
        v(no_validate,
          {"--disable-validation"},
          "Disable cpu validation, so only gpu version is ran");
        v(repeat, {"--repeat"}, "Repeat the tests");
        v(rethrow, {"--rethrow"}, "Rethrow any exceptions found during verify");
    }

    struct per_arg
    {
        template <class T, class Action>
        void operator()(T& x, argument& a, Action action) const
        {
            action(x, a);
        }
    };

    template <class T, class... Fs>
    void add(T& x, std::string name, Fs... fs)
    {
        argument_index.insert(std::make_pair(name, arguments.size()));
        arguments.emplace_back();

        argument& arg   = arguments.back();
        arg.name        = name;
        arg.type        = miopen::get_type_name<T>();
        arg.write_value = [&](std::vector<std::string> params) { args::write_value{}(x, params); };
        arg.read_value  = [&] { return args::read_value{}(x); };
        miopen::each_args(std::bind(per_arg{}, std::ref(x), std::ref(arg), std::placeholders::_1),
                          fs...);
        // assert(get_argument(name).name == name);
    }

    void show_help()
    {
        std::cout << "Driver arguments: " << std::endl;
        this->parse([&](const auto& var, std::initializer_list<std::string> x, std::string help) {
            std::cout << std::endl;
            std::string prefix = "    ";
            for(const std::string& a : x)
            {
                std::cout << prefix;
                std::cout << a;
                prefix = ", ";
            }
            if(not is_same<bool>(var))
                std::cout << " [" << miopen::get_type_name(var) << "]";
            std::cout << std::endl;
            std::cout << "        " << help << std::endl;
        });
        std::cout << std::endl;
        std::cout << "Test inputs: " << std::endl;
        for(auto&& arg : this->arguments)
        {
            std::cout << "    --" << arg.name;
            if(not arg.type.empty())
                std::cout << " [" << arg.type << "]";
            std::cout << std::endl;
        }
        std::cout << std::endl;
    }

    void show_command()
    {
        std::cout << this->program_name << " ";
        for(auto&& arg : this->arguments)
        {
            std::string value = arg.read_value();
            if(not value.empty())
            {
                std::cout << "--" << arg.name << " ";
                if(value != arg.name)
                    std::cout << value << " ";
            }
        }
        std::cout << std::endl;
    }

    template <class X>
    struct generate_tensor_t
    {
        std::function<std::set<X>()> get_data;
        template <class T>
        void operator()(T& x, argument& arg) const
        {
            arg.add_source(get_data, x);
            unsigned long max_value = x.desc.GetType() == miopenHalf ? 5 : 17;
            arg.post_write_actions.push_back(
                [&x, max_value] { tensor_generate{}(x, rand_gen{max_value}); });
        }
    };

    template <class X>
    generate_tensor_t<X> generate_tensor(std::set<X> dims, X single)
    {
        return {[=]() -> std::set<X> {
            if(full_set)
                return dims;
            else
                return {single};
        }};
    }

    template <class X>
    generate_tensor_t<std::vector<X>> generate_tensor(std::set<std::vector<X>> dims,
                                                      std::initializer_list<X> single)
    {
        return generate_tensor<std::vector<X>>(dims, single);
    }

    template <class F>
    auto lazy_generate_tensor(F f) -> generate_tensor_t<miopen::range_value<decltype(f())>>
    {
        return {[=]() -> decltype(f()) {
            if(full_set)
                return f();
            else
                return {*f().begin()};
        }};
    }

    template <class F, class X>
    generate_tensor_t<X> lazy_generate_tensor(F f, X single)
    {
        return {[=]() -> std::set<X> {
            if(full_set)
                return f();
            else
                return {single};
        }};
    }

    template <class F, class X>
    generate_tensor_t<std::vector<X>> lazy_generate_tensor(F f, std::initializer_list<X> single)
    {
        return lazy_generate_tensor<F, std::vector<X>>(f, single);
    }

    generate_tensor_t<std::vector<int>> get_bn_spatial_input_tensor()
    {
        return lazy_generate_tensor([=] { return get_bn_spatial_inputs(batch_factor); },
                                    {4, 64, 28, 28});
    }

    generate_tensor_t<std::vector<int>> get_bn_peract_input_tensor()
    {
        return lazy_generate_tensor([=] { return get_bn_peract_inputs(batch_factor); },
                                    {16, 32, 8, 8});
    }

    generate_tensor_t<std::vector<int>> get_input_tensor()
    {
        return lazy_generate_tensor([=] { return get_inputs(batch_factor); }, {16, 32, 8, 8});
    }

    generate_tensor_t<std::vector<int>> get_weights_tensor()
    {
        return lazy_generate_tensor([=] { return get_weights(batch_factor); }, {64, 32, 5, 5});
    }

    template <class X>
    struct generate_data_t
    {
        std::function<X()> get_data;
        template <class T>
        void operator()(T& x, argument& arg) const
        {
            arg.add_source(get_data, x);
        }
    };

    template <class T>
    generate_data_t<std::vector<T>> generate_data(std::vector<T> dims, T single)
    {
        return {[=]() -> std::vector<T> {
            if(full_set)
                return dims;
            else
                return {single};
        }};
    }

    template <class T>
    generate_data_t<std::vector<T>> generate_data(std::initializer_list<T> dims)
    {
        return generate_data(std::vector<T>(dims));
    }

    template <class T>
    generate_data_t<std::vector<std::vector<T>>>
    generate_data(std::initializer_list<std::initializer_list<T>> dims)
    {
        return generate_data(std::vector<std::vector<T>>(dims.begin(), dims.end()));
    }

    template <class T>
    generate_data_t<std::vector<T>> generate_data(std::vector<T> dims)
    {
        return {[=]() -> std::vector<T> {
            if(full_set)
                return dims;
            else
                return {dims.front()};
        }};
    }

    template <class F, class T>
    auto lazy_generate_data(F f, T single) -> generate_data_t<decltype(f())>
    {
        return {[=]() -> decltype(f()) {
            if(full_set)
                return f();
            else
                return {single};
        }};
    }

    template <class F>
    auto lazy_generate_data(F f) -> generate_data_t<decltype(f())>
    {
        return {[=]() -> decltype(f()) {
            if(full_set)
                return f();
            else
                return {f().front()};
        }};
    }

    template <class T>
    generate_data_t<std::vector<T>> generate_single(T single)
    {
        return {[=]() -> std::vector<T> { return {single}; }};
    }

    template <class X>
    struct set_value_t
    {
        X value;
        template <class T>
        void operator()(T& x, argument& arg) const
        {
            auto y          = value;
            arg.type        = "";
            arg.write_value = [&x, y](std::vector<std::string> as) {
                if(not as.empty())
                    throw std::runtime_error("Argument should not have any additional parameters");
                x = y;
            };
            arg.read_value = [&x, &arg, y]() -> std::string {
                if(x == y)
                    return arg.name;
                else
                    return "";
            };
        }
    };

    template <class T>
    set_value_t<T> set_value(T x)
    {
        return {x};
    }

    set_value_t<bool> flag() { return set_value(true); }

    template <class CpuRange, class GpuRange, class Fail>
    std::pair<CpuRange, GpuRange> verify_check(CpuRange out_cpu, GpuRange out_gpu, Fail fail)
    {
        CHECK(miopen::range_distance(out_cpu) == miopen::range_distance(out_gpu));

        using value_type = miopen::range_value<decltype(out_gpu)>;
        double threshold = std::numeric_limits<value_type>::epsilon() * tolerance;
        auto error       = miopen::rms_range(out_cpu, out_gpu);
        if(not(error <= threshold) or verbose)
        {
            std::cout << (error <= threshold ? "error: " : "FAILED: ") << error << std::endl;
            if(not verbose)
            {
                show_command();
                fail(-1);
            }

            auto mxdiff = miopen::max_diff(out_cpu, out_gpu);
            std::cout << "Max diff: " << mxdiff << std::endl;
            //            auto max_idx = miopen::mismatch_diff(out_cpu, out_gpu, mxdiff);
            //            std::cout << "Max diff at " << max_idx << ": " << out_cpu[max_idx] << " !=
            //            " << out_gpu[max_idx] << std::endl;

            if(miopen::range_zero(out_cpu))
                std::cout << "Cpu data is all zeros" << std::endl;
            if(miopen::range_zero(out_gpu))
                std::cout << "Gpu data is all zeros" << std::endl;

            auto idx = miopen::mismatch_idx(out_cpu, out_gpu, miopen::float_equal);
            if(idx < miopen::range_distance(out_cpu))
            {
                std::cout << "Mismatch at " << idx << ": " << out_cpu[idx] << " != " << out_gpu[idx]
                          << std::endl;
            }

            auto cpu_nan_idx = find_idx(out_cpu, miopen::not_finite);
            if(cpu_nan_idx >= 0)
                std::cout << "Non finite number found in cpu at " << cpu_nan_idx << ": "
                          << out_cpu[cpu_nan_idx] << std::endl;

            auto gpu_nan_idx = find_idx(out_gpu, miopen::not_finite);
            if(gpu_nan_idx >= 0)
                std::cout << "Non finite number found in gpu at " << gpu_nan_idx << ": "
                          << out_gpu[gpu_nan_idx] << std::endl;
        }
        else if(miopen::range_zero(out_cpu) and miopen::range_zero(out_gpu))
        {
            std::cout << "Warning: Both CPU and GPU data is all zero" << std::endl;
            show_command();
            fail(-1);
        }
        // std::cout << "----- END VERIFY CHECK -----\n" << std::endl;
        return std::make_pair(std::move(out_cpu), std::move(out_gpu));
    }

    struct verify_check_t
    {
        template <class Self, class CpuRange, class GpuRange, class Fail, class I>
        auto operator()(Self self, CpuRange out_cpu, GpuRange out_gpu, Fail fail, I i) const
            MIOPEN_RETURNS(self->verify_check(std::get<I{}>(out_cpu),
                                              std::get<I{}>(out_gpu),
                                              std::bind(fail, i)))
    };

    struct verify_check_make_tuples
    {
        template <class... Ts>
        auto operator()(Ts... xs) const
            MIOPEN_RETURNS(std::make_pair(std::make_tuple(std::move(xs.first)...),
                                          std::make_tuple(std::move(xs.second)...)))
    };

    template <class... CpuRanges, class... GpuRanges, class Fail>
    std::pair<std::tuple<CpuRanges...>, std::tuple<GpuRanges...>>
    verify_check(std::tuple<CpuRanges...> out_cpu, std::tuple<GpuRanges...> out_gpu, Fail fail)
    {
        static_assert(sizeof...(CpuRanges) == sizeof...(GpuRanges), "Cpu and gpu mismatch");
        return miopen::sequence(miopen::by(verify_check_make_tuples{},
                                           std::bind(verify_check_t{},
                                                     this,
                                                     std::move(out_cpu),
                                                     std::move(out_gpu),
                                                     fail,
                                                     std::placeholders::_1)))(
            std::integral_constant<std::size_t, sizeof...(CpuRanges)>{});
    }

    template <class F, class V, class... Ts>
    auto verify_impl(F&& f, V&& v, Ts&&... xs)
        -> decltype(std::make_pair(v.cpu(xs...), v.gpu(xs...)))
    {
        decltype(v.cpu(xs...)) cpu;
        decltype(v.gpu(xs...)) gpu;

        if(verbose or time)
        {
            show_command();
            v.fail(std::integral_constant<int, -1>{}, xs...);
        }
        try
        {
            auto&& h = get_handle();
            // Compute cpu
            std::future<decltype(v.cpu(xs...))> cpuf;
            if(not no_validate)
            {
                cpuf = cpu_async(v, xs...);
            }
            // Compute gpu
            if(time)
            {
                h.EnableProfiling();
                h.ResetKernelTime();
            }
            gpu = v.gpu(xs...);
            if(time)
            {
                std::cout << "Kernel time: " << h.GetKernelTime() << " ms" << std::endl;
                h.EnableProfiling(false);
            }
            // Validate
            if(!no_validate)
            {
                cpu = cpuf.get();
                f(cpu, gpu);
            }
        }
        catch(const std::exception& ex)
        {
            std::cout << "FAILED: " << ex.what() << std::endl;
            show_command();
            v.fail(-1, xs...);
            if(rethrow)
                throw;
        }
        catch(...)
        {
            std::cout << "FAILED with unknown exception" << std::endl;
            show_command();
            v.fail(-1, xs...);
            if(rethrow)
                throw;
        }
        if(no_validate)
        {
            return std::make_pair(gpu, gpu);
        }
        else
        {
            return std::make_pair(cpu, gpu);
        }
    }

    template <class V, class... Ts>
    auto verify(V&& v, Ts&&... xs) -> decltype(std::make_pair(v.cpu(xs...), v.gpu(xs...)))
    {
        // Use std::function here to workaround ICE on gcc 5
        // See: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=70100
        std::function<void(int)> fm = [&](int mode) { v.fail(mode, xs...); };
        return verify_impl(
            [&](auto&& cpu, auto&& gpu) {
                // Use this explictly to avoid ICE on gcc 5
                this->verify_check(cpu, gpu, fm);
            },
            v,
            xs...);
    }

    template <class V, class... Ts>
    auto verify_equals(V&& v, Ts&&... xs) -> decltype(std::make_pair(v.cpu(xs...), v.gpu(xs...)))
    {
        return verify_impl(
            [&](auto&& cpu, auto&& gpu) {
                if(miopen::range_zero(cpu))
                {
                    std::cout << "Cpu data is all zeros" << std::endl;
                    v.fail(-1, xs...);
                }

                if(miopen::range_zero(gpu))
                {
                    std::cout << "Gpu data is all zeros" << std::endl;
                    v.fail(-1, xs...);
                }

                auto idx = miopen::mismatch_idx(cpu, gpu, miopen::float_equal);
                if(idx < miopen::range_distance(cpu))
                {
                    std::cout << "FAILED" << std::endl;
                    std::cout << "Mismatch at " << idx << ": " << cpu[idx] << " != " << gpu[idx]
                              << std::endl;
                    show_command();
                    v.fail(-1, xs...);
                }
            },
            v,
            xs...);
    }
};

template <class Iterator, class Action>
void run_data(Iterator start, Iterator last, Action a)
{
    if(start == last)
    {
        a();
        return;
    }

    auto&& sources = (*start)->data_sources;
    if(sources.empty())
    {
        run_data(std::next(start), last, a);
    }
    else
        for(auto&& src : sources)
        {
            src([=] { run_data(std::next(start), last, a); });
        }
}

struct keyword_set
{
    std::set<std::string>* value;
    keyword_set(std::set<std::string>& x) : value(&x) {}
    template <class T>
    void operator()(T&&, std::initializer_list<std::string> x, std::string) const
    {
        value->insert(x);
    }
};

struct parser
{
    args::string_map* m;
    parser(args::string_map& x) : m(&x) {}
    template <class T>
    void operator()(T& x, std::initializer_list<std::string> keywords, std::string) const
    {
        for(auto&& keyword : keywords)
        {
            if(m->count(keyword) > 0)
            {
                try
                {
                    args::write_value{}(x, (*m)[keyword]);
                    return;
                }
                catch(...)
                {
                    std::cerr << "Invalid argument: " << keyword << std::endl;
                    throw;
                }
            }
        }
    }

    void operator()(bool& x, std::initializer_list<std::string> keywords, std::string) const
    {
        for(auto&& keyword : keywords)
        {
            if(m->count(keyword) > 0)
            {
                x = true;
                return;
            }
        }
    }
};

template <class Driver>
void test_drive_impl(std::string program_name, std::vector<std::string> as)
{
    Driver d{};
    d.program_name = program_name;

    std::set<std::string> keywords{"--help", "-h", "--half", "--float", "--double"};
    d.parse(keyword_set{keywords});
    auto arg_map = args::parse(as, [&](std::string x) {
        return (keywords.count(x) > 0) or
               ((x.compare(0, 2, "--") == 0) and d.has_argument(x.substr(2)));
    });

    if(arg_map.count("--half") > 0)
    {
        d.type = miopenHalf;
    }
    else if(arg_map.count("--double") > 0)
    {
        throw std::runtime_error("Double is not supported");
    }
    else
    {
        d.type = miopenFloat;
    }

    // Show help
    if((arg_map.count("-h") > 0) or (arg_map.count("--help") > 0))
    {
        d.show_help();
        return;
    }

    d.parse(parser{arg_map});

    for(auto&& p : arg_map)
    {
        if(p.first.empty())
        {
            std::cerr << "Unused arguments: " << std::endl;
            for(auto&& s : p.second)
                std::cerr << "    " << s << std::endl;
            std::abort();
        }
        else if(keywords.count(p.first) == 0)
        {
            assert(p.first.length() > 2);
            auto name = p.first.substr(2);
            try
            {
                auto&& arg = d.get_argument(name);
                arg.write(p.second);
            }
            catch(const std::exception& ex)
            {
                std::cerr << "Invalid argument: " << name << std::endl;
                std::cerr << "With parameters: " << std::endl;
                for(auto&& s : p.second)
                    std::cerr << "    " << s << std::endl;
                std::cerr << ex.what() << std::endl;
                std::abort();
            }
            catch(...)
            {
                std::cerr << "Invalid argument: " << name << std::endl;
                std::cerr << "With parameters: " << std::endl;
                for(auto&& s : p.second)
                    std::cerr << "    " << s << std::endl;
                throw;
            }
        }
    }

    // Run data on arguments that are not passed in
    std::vector<typename Driver::argument*> data_args;
    for(auto&& arg : d.arguments)
    {
        if(arg_map.count("--" + arg.name) == 0)
        {
            data_args.push_back(&arg);
        }
    }
    for(int i = 0; i < d.repeat; i++)
        run_data(data_args.begin(), data_args.end(), [&] { d.run(); });
}

template <class Driver>
void test_drive(int argc, const char* argv[])
{
    std::vector<std::string> as(argv + 1, argv + argc);
    test_drive_impl<Driver>(argv[0], std::move(as));
}

template <template <class...> class Driver>
void test_drive(int argc, const char* argv[])
{
    std::vector<std::string> as(argv + 1, argv + argc);
    as.emplace_back("--float");
    for(auto&& arg : as)
    {
        if(arg == "--half")
        {
            test_drive_impl<Driver<half_float::half>>(argv[0], std::move(as));
            break;
        }
        if(arg == "--float")
        {
            test_drive_impl<Driver<float>>(argv[0], std::move(as));
            break;
        }
        if(arg == "--double")
        {
            // test_drive_impl<Driver<double>>(argv[0], std::move(as));
            break;
        }
    }
}
